{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO)
import Control.Monad.IO.Class (liftIO)

import Data.Aeson
    ( FromJSON(..)
    , encode
    , object
    , withObject
    , (.:)
    , (.=)
    )

import Database.PostgreSQL.Simple (Connection)

import Domain.Payment

import Gateway.AppGateway
import Gateway.Gateway (GatewayError(..))
import Gateway.MockGateway (MockGateway(..))
import Gateway.StripeGateway (createStripeGateway)

import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)

import Repository.Database
import qualified Repository.PaymentRepository as PaymentRepository
import qualified Repository.RedisRepository as RedisRepository

import Servant

import Service.PaymentRouter (GatewayCandidate(..))
import qualified Service.PaymentService as PaymentService

import qualified Monitoring.Metrics as Metrics

import qualified Worker.PaymentWorker as PaymentWorker

import System.Environment (lookupEnv)
import System.Random (randomIO)


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
       "v1" :> "health"
           :> Get '[JSON] String

  :<|> "v1" :> "metrics"
      :> Get '[JSON] Metrics.MetricsResponse

  :<|> "v1" :> "jobs"
      :> ReqBody '[PlainText] String
      :> Post '[JSON] String

  :<|> "v1" :> "payments"
      :> Header "Idempotency-Key" String
      :> ReqBody '[JSON] CreatePaymentRequest
      :> Post '[JSON] Payment

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> Get '[JSON] Payment

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> "status"
      :> ReqBody '[JSON] PaymentStatus
      :> Patch '[JSON] Payment

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> "capture"
      :> Post '[JSON] Payment

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> "refund"
      :> Post '[JSON] Payment

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> "reconcile"
      :> QueryParam' '[Required] "gatewayStatus" String
      :> QueryParam' '[Required] "gateway" String
      :> Post '[JSON] String

  :<|> "v1" :> "payments"
      :> Capture "paymentId" String
      :> "reconcile-async"
      :> QueryParam' '[Required] "gatewayStatus" String
      :> QueryParam' '[Required] "gateway" String
      :> Post '[JSON] String

  :<|> "v1" :> "webhooks"
      :> Capture "gateway" String
      :> ReqBody '[JSON] WebhookRequest
      :> Post '[JSON] String


apiProxy :: Proxy API
apiProxy = Proxy


server
    :: Connection
    -> Metrics.Metrics
    -> [GatewayCandidate AppGateway]
    -> Server API
server connection metrics candidates =
       health
  :<|> metricsHandler metrics
  :<|> enqueueJobHandler
  :<|> createPayment connection metrics candidates
  :<|> getPaymentHandler connection
  :<|> updatePaymentStatusHandler connection
  :<|> capturePaymentHandler connection
  :<|> refundPaymentHandler connection
  :<|> reconcilePaymentHandler connection metrics
  :<|> reconcilePaymentAsyncHandler
  :<|> webhookHandler connection


health :: Handler String
health =
    pure "PaySwitch is healthy"


metricsHandler
    :: Metrics.Metrics
    -> Handler Metrics.MetricsResponse
metricsHandler metrics =
    liftIO $
        Metrics.toMetricsResponse metrics


enqueueJobHandler
    :: String
    -> Handler String
enqueueJobHandler job = do
    result <- liftIO $ do
        redisConnection <-
            RedisRepository.connectRedis

        RedisRepository.enqueueJob
            redisConnection
            "payswitch:jobs"
            job

    if result
        then
            pure "Job enqueued"
        else
            throwError err500
                { errBody =
                    "Failed to enqueue job"
                }


createPayment
    :: Connection
    -> Metrics.Metrics
    -> [GatewayCandidate AppGateway]
    -> Maybe String
    -> CreatePaymentRequest
    -> Handler Payment
createPayment connection metrics candidates idempotencyKey request = do

    liftIO $
        Metrics.incrementPaymentsTotal metrics

    case idempotencyKey of

        Nothing ->
            throwError err400
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                ("Idempotency-Key header is required"
                                    :: String)
                            ]
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
                                { errBody =
                                    encode
                                        (object
                                            [ "error" .=
                                                ("Idempotency record is invalid"
                                                    :: String)
                                            ]
                                        )
                                }

                Nothing -> do

                    uniqueNumber <- liftIO randomIO

                    let generatedId =
                            "pay_" ++
                            show (abs (uniqueNumber :: Int))

                    result <- liftIO $
                        PaymentService.createPayment
                            connection
                            candidates
                            request
                            generatedId

                    case result of

                        Left errorMessage -> do
                            liftIO $
                                Metrics.incrementPaymentsFailed metrics

                            throwError err400
                                { errBody =
                                    encode
                                        (object
                                            [ "error" .=
                                                errorMessage
                                            ]
                                        )
                                }

                        Right payment -> do

                            liftIO $
                                Metrics.incrementPaymentsSuccess metrics

                            liftIO $
                                PaymentRepository.saveIdempotencyKey
                                    connection
                                    key
                                    generatedId

                            pure payment


getPaymentHandler
    :: Connection
    -> String
    -> Handler Payment
getPaymentHandler connection requestedId = do

    result <- liftIO $
        PaymentRepository.getPayment
            connection
            requestedId

    case result of

        Nothing ->
            throwError err404
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                ("Payment not found"
                                    :: String)
                            ]
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
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                errorMessage
                            ]
                        )
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
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                errorMessage
                            ]
                        )
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
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                errorMessage
                            ]
                        )
                }

        Right payment ->
            pure payment


reconcilePaymentHandler
    :: Connection
    -> Metrics.Metrics
    -> String
    -> String
    -> String
    -> Handler String
reconcilePaymentHandler connection metrics requestedId gatewayStatusValue gatewayName = do

    result <- liftIO $
        PaymentService.reconcilePayment
            connection
            requestedId
            gatewayName
            gatewayStatusValue

    case result of

        Left errorMessage ->
            throwError err400
                { errBody =
                    encode
                        (object
                            [ "error" .=
                                errorMessage
                            ]
                        )
                }

        Right reconciliationStatus -> do

            if reconciliationStatus == "MATCH"
                then
                    liftIO $
                        Metrics.incrementReconciliationMatches
                            metrics
                else
                    liftIO $
                        Metrics.incrementReconciliationMismatches
                            metrics

            pure reconciliationStatus


reconcilePaymentAsyncHandler
    :: String
    -> String
    -> String
    -> Handler String
reconcilePaymentAsyncHandler
    requestedId
    gatewayStatusValue
    gatewayName = do

    result <- liftIO $ do

        redisConnection <-
            RedisRepository.connectRedis

        RedisRepository.enqueueJob
            redisConnection
            "payswitch:jobs"
            ( requestedId
                ++ "|"
                ++ gatewayName
                ++ "|"
                ++ gatewayStatusValue
            )

    if result
        then
            pure "Reconciliation job queued"
        else
            throwError err500
                { errBody =
                    "Failed to enqueue reconciliation job"
                }


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
                        { errBody =
                            encode
                                (object
                                    [ "error" .=
                                        ("Payment not found"
                                            :: String)
                                    ]
                                )
                        }

                Just payment -> do

                    let newStatus =
                            webhookStatus eventTypeValue

                    case newStatus of

                        Nothing ->
                            throwError err400
                                { errBody =
                                    encode
                                        (object
                                            [ "error" .=
                                                ("Unsupported webhook event type"
                                                    :: String)
                                            ]
                                        )
                                }

                        Just statusValue -> do

                            liftIO $
                                PaymentRepository.saveWebhookEvent
                                    connection
                                    (webhookEventId webhook)
                                    gatewayName
                                    (Just paymentIdValue)
                                    eventTypeValue
                                    payloadValue

                            let transitionValid =
                                    PaymentService.isValidWebhookTransition
                                        (status payment)
                                        statusValue

                            if not transitionValid

                                then
                                    throwError err409
                                        { errBody =
                                            encode
                                                (object
                                                    [ "error" .=
                                                        ("Invalid webhook state transition"
                                                            :: String)
                                                    ]
                                                )
                                        }

                                else do

                                    updated <- liftIO $
                                        PaymentRepository.updatePaymentStatus
                                            connection
                                            paymentIdValue
                                            statusValue

                                    if not updated

                                        then
                                            throwError err400
                                                { errBody =
                                                    encode
                                                        (object
                                                            [ "error" .=
                                                                ("Failed to update payment status"
                                                                    :: String)
                                                            ]
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
                                                    pure
                                                        "Webhook processed successfully"

                                                else
                                                    throwError err500
                                                        { errBody =
                                                            encode
                                                                (object
                                                                    [ "error" .=
                                                                        ("Failed to mark webhook as processed"
                                                                            :: String)
                                                                    ]
                                                                )
                                                        }


webhookStatus
    :: String
    -> Maybe PaymentStatus
webhookStatus "payment.succeeded" =
    Just Success

webhookStatus "payment.failed" =
    Just Failed

webhookStatus "payment.pending" =
    Just Pending

webhookStatus "payment.captured" =
    Just Captured

webhookStatus "payment.refunded" =
    Just Refunded

webhookStatus _ =
    Nothing


app
    :: Connection
    -> Metrics.Metrics
    -> [GatewayCandidate AppGateway]
    -> Application
app connection metrics candidates =
    serve
        apiProxy
        (server connection metrics candidates)


main :: IO ()
main = do

    connection <-
        Repository.Database.createConnection

    metrics <-
        Metrics.newMetrics

    putStrLn
        "Connected to PostgreSQL"

    stripeSecretKey <-
        lookupEnv "STRIPE_SECRET_KEY"

    stripePaymentMethod <-
        lookupEnv "STRIPE_TEST_PAYMENT_METHOD"

    stripeGateway <-
        case
            (stripeSecretKey, stripePaymentMethod)
        of

            (Just secretKey, Just paymentMethod) -> do

                putStrLn
                    "Stripe gateway configured"

                Just <$>
                    createStripeGateway
                        secretKey
                        paymentMethod

            _ -> do

                putStrLn
                    "Stripe gateway not configured"

                pure Nothing


    let mockGatewayA =
            MockGateway
                { mockGatewayName =
                    "MockGateway-A"

                , mockGatewayError =
                    Nothing
                }

        mockGatewayB =
            MockGateway
                { mockGatewayName =
                    "MockGateway-B"

                , mockGatewayError =
                    Nothing
                }

        baseCandidates =
            [ GatewayCandidate
                "MockGateway-A"
                3
                (AppMock mockGatewayA)

            , GatewayCandidate
                "MockGateway-B"
                2
                (AppMock mockGatewayB)
            ]

        candidates =
            case stripeGateway of

                Nothing ->
                    baseCandidates

                Just gateway ->
                    GatewayCandidate
                        "Stripe"
                        1
                        (AppStripe gateway)
                    : baseCandidates


    _ <-
        forkIO
            PaymentWorker.runWorker

    putStrLn
        "PaySwitch background worker started"

    putStrLn
        "PaySwitch API running on http://localhost:8080"

    run
        8080
        (app connection metrics candidates)