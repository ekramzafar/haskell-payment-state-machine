module Service.PaymentRouter where

import Database.PostgreSQL.Simple (Connection)
import Domain.Payment (Payment(..))
import Gateway.Gateway
import qualified Repository.PaymentRepository as PaymentRepository

data GatewayCandidate gateway = GatewayCandidate
    { candidateName :: String
    , candidatePriority :: Int
    , candidateGateway :: gateway
    }

isRetryable :: GatewayError -> Bool
isRetryable GatewayTimeout = True
isRetryable GatewayUnavailable = True
isRetryable PaymentDeclined = False
isRetryable InsufficientFunds = False
isRetryable InvalidPaymentMethod = False

gatewayErrorMessage :: GatewayError -> String
gatewayErrorMessage GatewayTimeout = "Gateway timeout"
gatewayErrorMessage GatewayUnavailable = "Gateway unavailable"
gatewayErrorMessage PaymentDeclined = "Payment declined"
gatewayErrorMessage InsufficientFunds = "Insufficient funds"
gatewayErrorMessage InvalidPaymentMethod = "Invalid payment method"

loadRoutedGateways
    :: Connection
    -> Payment
    -> [GatewayCandidate gateway]
    -> IO [GatewayCandidate gateway]
loadRoutedGateways connection payment candidates = do
    rules <- PaymentRepository.getRoutingRules
        connection
        (currency payment)
        (paymentMethod payment)

    let routedCandidates =
            [ candidate
                { candidatePriority = priority
                }
            | candidate <- candidates
            , Just priority <-
                [lookup (candidateName candidate) rules]
            ]

    healthyCandidates <- filterHealthyGateways
        connection
        routedCandidates

    pure (sortByPriority healthyCandidates)

filterHealthyGateways
    :: Connection
    -> [GatewayCandidate gateway]
    -> IO [GatewayCandidate gateway]
filterHealthyGateways connection candidates = do
    results <- mapM checkHealth candidates

    pure
        [ candidate
        | (candidate, healthy) <- results
        , healthy
        ]
  where
    checkHealth candidate = do
        health <- PaymentRepository.getGatewayHealth
            connection
            (candidateName candidate)

        case health of
            Just (enabled, _, circuitState) -> do
                halfOpen <-
                    if enabled && circuitState == "OPEN"
                        then PaymentRepository.tryHalfOpen
                            connection
                            (candidateName candidate)
                        else pure False

                pure
                    ( candidate
                    , enabled
                        && ( circuitState /= "OPEN"
                             || halfOpen
                           )
                    )

            Nothing ->
                pure (candidate, False)

sortByPriority
    :: [GatewayCandidate gateway]
    -> [GatewayCandidate gateway]
sortByPriority [] = []
sortByPriority (candidate : remaining) =
    insertByPriority candidate
        (sortByPriority remaining)

insertByPriority
    :: GatewayCandidate gateway
    -> [GatewayCandidate gateway]
    -> [GatewayCandidate gateway]
insertByPriority candidate [] =
    [candidate]

insertByPriority candidate (first : remaining)
    | candidatePriority candidate <= candidatePriority first =
        candidate : first : remaining
    | otherwise =
        first : insertByPriority candidate remaining

routePayment
    :: Gateway gateway
    => Connection
    -> Payment
    -> [GatewayCandidate gateway]
    -> IO (Either String Payment)
routePayment connection payment candidates = do
    routedCandidates <- loadRoutedGateways
        connection
        payment
        candidates

    tryGateways routedCandidates
  where
    tryGateways [] =
        pure (Left "No healthy payment gateways available")

    tryGateways (candidate : remaining) = do

        -- Record that this gateway is being attempted.
        PaymentRepository.savePaymentEvent
            connection
            (paymentId payment)
            "gateway_attempt"
            (Just (candidateName candidate))
            Nothing

        result <- authorize
            (candidateGateway candidate)
            payment

        case result of
            GatewaySuccess -> do

                PaymentRepository.savePaymentAttempt
                    connection
                    (paymentId payment)
                    (candidateName candidate)
                    "Success"
                    Nothing

                PaymentRepository.savePaymentEvent
                    connection
                    (paymentId payment)
                    "gateway_success"
                    (Just (candidateName candidate))
                    Nothing

                PaymentRepository.recordGatewaySuccess
                    connection
                    (candidateName candidate)

                pure (Right payment)

            GatewayFailure gatewayError -> do
                let errorMessage =
                        gatewayErrorMessage gatewayError

                PaymentRepository.savePaymentAttempt
                    connection
                    (paymentId payment)
                    (candidateName candidate)
                    "Failed"
                    (Just errorMessage)

                PaymentRepository.savePaymentEvent
                    connection
                    (paymentId payment)
                    "gateway_failed"
                    (Just (candidateName candidate))
                    (Just errorMessage)

                PaymentRepository.recordGatewayFailure
                    connection
                    (candidateName candidate)

                if isRetryable gatewayError
                    then do
                        PaymentRepository.savePaymentEvent
                            connection
                            (paymentId payment)
                            "gateway_retry"
                            (Just (candidateName candidate))
                            (Just errorMessage)

                        tryGateways remaining
                    else
                        pure (Left errorMessage)
