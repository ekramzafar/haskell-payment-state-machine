module Gateway.Gateway where

import Domain.Payment (Payment)

data GatewayError
    = GatewayTimeout
    | GatewayUnavailable
    | PaymentDeclined
    | InsufficientFunds
    | InvalidPaymentMethod
    deriving (Show, Eq)

data GatewayResult
    = GatewaySuccess
    | GatewayFailure GatewayError
    deriving (Show, Eq)

class Gateway gateway where
    authorize :: gateway -> Payment -> IO GatewayResult
    capture :: gateway -> Payment -> IO GatewayResult
    refund :: gateway -> Payment -> IO GatewayResult
