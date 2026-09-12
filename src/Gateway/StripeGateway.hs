module Gateway.StripeGateway
    ( StripeGateway(..)
    , createStripeGateway
    ) where

import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import Data.Aeson ((.:), (.:?))
import qualified Data.Aeson.Types as AesonTypes
import Data.Char (toLower)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as BL
import Domain.Payment (Payment(..))
import Gateway.Gateway
import Network.HTTP.Client
    ( Manager
    , RequestBody(..)
    , httpLbs
    , newManager
    , parseRequest
    , requestBody
    , requestHeaders
    , responseBody
    , responseStatus
    , method
    , responseTimeout
    , responseTimeoutMicro
    )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Header
    ( hAuthorization
    , hContentType
    )
import Network.HTTP.Types.Method (methodPost)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)


data StripeGateway = StripeGateway
    { stripeSecretKey :: String
    , stripePaymentMethod :: String
    , stripeManager :: Manager
    }

createStripeGateway :: String -> String -> IO StripeGateway
createStripeGateway secretKey paymentMethod = do
    manager <- newManager tlsManagerSettings

    pure StripeGateway
        { stripeSecretKey = secretKey
        , stripePaymentMethod = paymentMethod
        , stripeManager = manager
        }


instance Gateway StripeGateway where

    authorize gateway payment = do
        result <-
            try (createPaymentIntent gateway payment)
                :: IO (Either SomeException GatewayResult)

        case result of
            Left _ ->
                pure (GatewayFailure GatewayUnavailable)

            Right gatewayResult ->
                pure gatewayResult


    capture _ _ =
        pure GatewaySuccess


    refund _ _ =
        pure GatewaySuccess

createPaymentIntent
    :: StripeGateway
    -> Payment
    -> IO GatewayResult
createPaymentIntent gateway payment = do
    request <-
        parseRequest
            "https://api.stripe.com/v1/payment_intents"

    let body =
            BS.concat
                [ BS.pack "amount="
                , BS.pack (show (amount payment))
                , BS.pack "&currency="
                , urlEncode
                    False
                    (BS.pack (map toLower (currency payment)))
                , BS.pack "&payment_method="
                , urlEncode
                    False
                    (BS.pack (stripePaymentMethod gateway))
                , BS.pack "&confirm=true"
                , BS.pack "&payment_method_types[]=card"
                ]
                

        authenticatedRequest =
            request
                { method = methodPost
                , requestHeaders =
                    [ ( hAuthorization
                      , BS.pack
                            ("Bearer " ++ stripeSecretKey gateway)
                      )
                    , ( hContentType
                      , BS.pack
                            "application/x-www-form-urlencoded"
                      )
                    ]
                , requestBody =
                    RequestBodyBS body
                , responseTimeout =
                    responseTimeoutMicro 10000000
                }

    response <-
        httpLbs
            authenticatedRequest
            (stripeManager gateway)

    let code =
            statusCode (responseStatus response)

    if code >= 200 && code < 300
        then
            parseStripeSuccess
                (responseBody response)
        else
            parseStripeFailure
                (responseBody response)

parseStripeSuccess
    :: BL.ByteString
    -> IO GatewayResult
parseStripeSuccess body =

    case Aeson.decode body :: Maybe Aeson.Value of

        Nothing ->
            pure
                (GatewayFailure GatewayUnavailable)

        Just value ->

            case value of

                Aeson.Object object ->

                    case AesonTypes.parseMaybe
                        (\obj ->
                            obj .: AesonKey.fromString "status"
                        )
                        object of

                        Just ("succeeded" :: String) ->
                            pure GatewaySuccess

                        Just "requires_capture" ->
                            pure GatewaySuccess

                        Just "requires_action" ->
                            pure
                                (GatewayFailure GatewayUnavailable)

                        Just "requires_payment_method" ->
                            pure
                                (GatewayFailure PaymentDeclined)

                        Just "canceled" ->
                            pure
                                (GatewayFailure PaymentDeclined)

                        _ ->
                            pure
                                (GatewayFailure GatewayUnavailable)

                _ ->
                    pure
                        (GatewayFailure GatewayUnavailable)


parseStripeFailure
    :: BL.ByteString
    -> IO GatewayResult
parseStripeFailure body =

    case Aeson.decode body :: Maybe Aeson.Value of

        Nothing ->
            pure
                (GatewayFailure GatewayUnavailable)

        Just value ->

            case value of

                Aeson.Object object ->

                    case AesonTypes.parseMaybe
                        (\obj ->
                            obj .:? AesonKey.fromString "error"
                        )
                        object of

                        Just (Just (Aeson.Object errorObject)) ->
                            classifyStripeError errorObject

                        _ ->
                            pure
                                (GatewayFailure GatewayUnavailable)

                _ ->
                    pure
                        (GatewayFailure GatewayUnavailable)


classifyStripeError
    :: Aeson.Object
    -> IO GatewayResult
classifyStripeError errorObject = do

    let errorType =
            case AesonTypes.parseMaybe
                (\obj ->
                    obj .:? AesonKey.fromString "type"
                )
                errorObject of
                Just (Just value) -> value
                _ -> ""

        errorCode =
            case AesonTypes.parseMaybe
                (\obj ->
                    obj .:? AesonKey.fromString "code"
                )
                errorObject of
                Just (Just value) -> value
                _ -> ""

    if errorType == "card_error"
        || errorCode == "card_declined"

        then
            pure
                (GatewayFailure PaymentDeclined)

    else if errorType == "invalid_request_error"

        then
            pure
                (GatewayFailure InvalidPaymentMethod)

    else
        pure
            (GatewayFailure GatewayUnavailable)
