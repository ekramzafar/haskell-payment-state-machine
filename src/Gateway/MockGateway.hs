module Gateway.MockGateway where

import Domain.Payment (Payment)
import Gateway.Gateway

data MockGateway = MockGateway
    { mockGatewayName :: String
    , mockGatewayError :: Maybe GatewayError
    }
    deriving (Show, Eq)

instance Gateway MockGateway where
    authorize gateway _ =
        case mockGatewayError gateway of
            Nothing ->
                pure GatewaySuccess

            Just gatewayError ->
                pure (GatewayFailure gatewayError)

    capture _ _ =
        pure GatewaySuccess

    refund _ _ =
        pure GatewaySuccess
