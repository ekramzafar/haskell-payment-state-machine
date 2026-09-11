{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
    ( FromJSON(..)
    , encode
    , object
    , withObject
    , (.:)
    , (.=)
    )
import Domain.Payment
import Network.Wai.Handler.Warp (run)
import Servant
import qualified Service.PaymentService as PaymentService
import System.Random (randomIO)
import qualified Repository.Database
import Database.PostgreSQL.Simple (Connection)
import qualified Repository.PaymentRepository as PaymentRepository
import Gateway.MockGateway (MockGateway(..))
import Service.PaymentRouter (GatewayCandidate(..))
import Gateway.Gateway (GatewayError(..))

data WebhookRequest = WebhookRequest
    { webhookEventId :: String
    , webhookPaymentId :: String
    , webhookEventType :: String
    }
    deriving (Show, Eq)

instance FromJSON WebhookRequest where
    parseJSON = withObject "WebhookRequest" $ \obj ->
        WebhookRequest
            <$> obj .: "eventId"
            <*> obj .: "paymentId"
            <*> obj .: "eventType"

type API =
       "v1" :> "health" :> Get '[JSON] String

  :<|> "v1" :> "payments"
      :> Header "Idempotency-Key" String
      :> ReqBody '[JSON] CreatePaymentRequest
      :> Post '[JSON] Payment

  :<|> "v1" :> "payments" :> Capture "paymentId" String
      :> Get '[JSON] Payment

  :<|> "v1" :> "payments" :> Capture "paymentId" String
      :> "status"
      :> ReqBody '[JSON] PaymentStatus
      :> Patch '[JSON] Payment

  :<|> "v1" :> "payments" :> Capture "paymentId" String
      :> "capture"
      :> Post '[JSON] Payment

  :<|> "v1" :> "payments" :> Capture "paymentId" String
      :> "refund"
      :> Post '[JSON] Payment
  
    :<|> "v1" :> "payments" :> Capture "paymentId" String
      :> "reconcile"
      :> QueryParam' '[Required] "gatewayStatus" String
      :> QueryParam' '[Required] "gateway" String
      :> Post '[JSON] String

  

  :<|> "v1" :> "webhooks" :> Capture "gateway" String
      :> ReqBody '[JSON] WebhookRequest
      :> Post '[JSON] String


server connection =
       health
  :<|> createPayment connection
  :<|> getPaymentHandler connection
  :<|> updatePaymentStatusHandler connection
  :<|> capturePaymentHandler connection
  :<|> refundPaymentHandler connection
  :<|> reconcilePaymentHandler connection
  :<|> webhookHandler connection


health :: Handler String
health = pure "PaySwitch is healthy"


getPaymentHandler :: Connection -> String -> Handler Payment
getPaymentHandler connection requestedId = do
    result <- liftIO $
        PaymentRepository.getPayment connection requestedId

    case result of
        Nothing ->
            throwError err404
                { errBody = encode (object
                    ["error" .= ("Payment not found" :: String)]
                    )
                }

        Just payment ->
            pure payment


updatePaymentStatusHandler
    :: Connection
    -> String
    -> PaymentStatus
    -> Handler Payment
updatePaymentStatusHandler connection requestedId newStatus = do
    result <- liftIO $
        PaymentService.updatePaymentStatus
            connection
            requestedId
            newStatus

    case result of
        Left errorMessage ->
            throwError err400
                { errBody = encode
                    (object ["error" .= errorMessage])
                }

        Right payment ->
            pure payment


capturePaymentHandler
    :: Connection
    -> String
    -> Handler Payment
capturePaymentHandler connection requestedId = do
    result <- liftIO $
        PaymentService.capturePayment
            connection
            requestedId

    case result of
        Left errorMessage ->
            throwError err400
                { errBody = encode
                    (object ["error" .= errorMessage])
                }

        Right payment ->
            pure payment


refundPaymentHandler
    :: Connection
    -> String
    -> Handler Payment
refundPaymentHandler connection requestedId = do
    result <- liftIO $
        PaymentService.refundPayment
            connection
            requestedId

    case result of
        Left errorMessage ->
            throwError err400
                { errBody = encode
                    (object ["error" .= errorMessage])
                }

        Right payment ->
            pure payment

reconcilePaymentHandler
    :: Connection
    -> String
    -> String
    -> String
    -> Handler String
reconcilePaymentHandler connection requestedId gatewayStatusValue gatewayName = do
    result <- liftIO $
        PaymentService.reconcilePayment
            connection
            requestedId
            gatewayName
            gatewayStatusValue

    case result of
        Left errorMessage ->
            throwError err400
                { errBody = encode
                    (object ["error" .= errorMessage])
                }

        Right reconciliationStatus ->
            pure reconciliationStatus

createPayment
    :: Connection
    -> Maybe String
    -> CreatePaymentRequest
    -> Handler Payment
createPayment connection idempotencyKey request = do
    case idempotencyKey of
        Nothing ->
            throwError err400
                { errBody = encode (object
                    ["error" .= ("Idempotency-Key header is required" :: String)]
                    )
                }

        Just key -> do
            existingPaymentId <- liftIO $
                PaymentRepository.getPaymentIdByIdempotencyKey
                    connection
                    key

            case existingPaymentId of
                Just existingId -> do
                    existingPayment <- liftIO $
                        PaymentRepository.getPayment
                            connection
                            existingId

                    case existingPayment of
                        Just payment ->
                            pure payment

                        Nothing ->
                            throwError err500
                                { errBody = encode (object
                                    ["error" .=
                                        ("Idempotency record is invalid" :: String)]
                                    )
                                }

                Nothing -> do
                    uniqueNumber <- liftIO randomIO

                    let generatedId =
                            "pay_" ++ show (abs (uniqueNumber :: Int))

                    result <- liftIO $
                        PaymentService.createPayment
                            connection
                            [ GatewayCandidate
                                  "MockGateway-A"
                                  999
                                  (MockGateway
                                      "MockGateway-A"
                                      (Just GatewayTimeout))
                            , GatewayCandidate
                                  "MockGateway-B"
                                  999
                                  (MockGateway
                                      "MockGateway-B"
                                      Nothing)
                            ]
                            request
                            generatedId

                    case result of
                        Left errorMessage ->
                            throwError err400
                                { errBody = encode
                                    (object ["error" .= errorMessage])
                                }

                        Right payment -> do
                            liftIO $
                                PaymentRepository.saveIdempotencyKey
                                    connection
                                    key
                                    generatedId

                            pure payment


webhookHandler
    :: Connection
    -> String
    -> WebhookRequest
    -> Handler String
webhookHandler connection gatewayName webhook = do

    existingEvent <- liftIO $
        PaymentRepository.webhookEventExists
            connection
            (webhookEventId webhook)

    if existingEvent
        then
            pure "Webhook already processed"

        else do
            let paymentIdValue =
                    webhookPaymentId webhook

                eventTypeValue =
                    webhookEventType webhook

                payloadValue =
                    "{\"eventId\":\""
                        ++ webhookEventId webhook
                        ++ "\",\"paymentId\":\""
                        ++ paymentIdValue
                        ++ "\",\"eventType\":\""
                        ++ eventTypeValue
                        ++ "\"}"

            existingPayment <- liftIO $
                PaymentRepository.getPayment
                    connection
                    paymentIdValue

            case existingPayment of
                Nothing ->
                    throwError err404
                        { errBody = encode (object
                            ["error" .=
                                ("Payment not found" :: String)]
                            )
                        }

                Just payment -> do

                    liftIO $
                        PaymentRepository.saveWebhookEvent
                            connection
                            (webhookEventId webhook)
                            gatewayName
                            (Just paymentIdValue)
                            eventTypeValue
                            payloadValue

                    let newStatus =
                            webhookStatus eventTypeValue

                    case newStatus of
                        Nothing ->
                            throwError err400
                                { errBody = encode (object
                                    ["error" .=
                                        ("Unsupported webhook event type"
                                            :: String)]
                                    )
                                }

                        Just statusValue -> do

                            updated <- liftIO $
                                PaymentRepository.updatePaymentStatus
                                    connection
                                    paymentIdValue
                                    statusValue

                            if not updated
                                then
                                    throwError err400
                                        { errBody = encode (object
                                            ["error" .=
                                                ("Failed to update payment status"
                                                    :: String)]
                                            )
                                        }

                                else do
                                    liftIO $
                                        PaymentRepository.savePaymentEvent
                                            connection
                                            paymentIdValue
                                            ("webhook_" ++ eventTypeValue)
                                            (Just gatewayName)
                                            Nothing

                                    processed <- liftIO $
                                        PaymentRepository.markWebhookProcessed
                                            connection
                                            (webhookEventId webhook)

                                    if processed
                                        then
                                            pure "Webhook processed successfully"
                                        else
                                            throwError err500
                                                { errBody =
                                                    encode
                                                        (object
                                                            [ "error"
                                                                .= ("Failed to mark webhook as processed" :: String)
                                                            ]
                                                        )
                                                }


webhookStatus :: String -> Maybe PaymentStatus
webhookStatus "payment.succeeded" = Just Success
webhookStatus "payment.failed" = Just Failed
webhookStatus "payment.pending" = Just Pending
webhookStatus "payment.captured" = Just Captured
webhookStatus "payment.refunded" = Just Refunded
webhookStatus _ = Nothing


app :: Connection -> Application
app connection =
    serve (Proxy :: Proxy API) (server connection)


main :: IO ()
main = do
    connection <- Repository.Database.createConnection
    putStrLn "Connected to PostgreSQL"
    putStrLn "PaySwitch API running on http://localhost:8080"
    run 8080 (app connection)
