{-# LANGUAGE OverloadedStrings #-}

module Repository.PaymentRepository where

import Data.Int (Int64)
import Database.PostgreSQL.Simple
    ( Connection
    , Only(..)
    , execute
    , query
    )

import Domain.Payment

savePayment :: Connection -> Payment -> IO ()
savePayment connection payment = do
    _ <- execute connection
        "INSERT INTO payments \
        \(payment_id, amount, currency, payment_method, status) \
        \VALUES (?, ?, ?, ?, ?)"
        ( paymentId payment
        , amount payment
        , currency payment
        , paymentMethod payment
        , show (status payment)
        )
    pure ()

savePaymentEvent
    :: Connection
    -> String
    -> String
    -> Maybe String
    -> Maybe String
    -> IO ()
savePaymentEvent connection paymentIdValue eventTypeValue gatewayValue detailsValue = do
    _ <- execute connection
        "INSERT INTO payment_events \
        \(payment_id, event_type, gateway, details) \
        \VALUES (?, ?, ?, ?)"
        ( paymentIdValue
        , eventTypeValue
        , gatewayValue
        , detailsValue
        )

    pure ()

saveWebhookEvent
    :: Connection
    -> String
    -> String
    -> Maybe String
    -> String
    -> String
    -> IO ()
saveWebhookEvent
    connection
    eventIdValue
    gatewayName
    paymentIdValue
    eventTypeValue
    payloadValue = do

    _ <- execute connection
        "INSERT INTO webhook_events \
        \(event_id, gateway, payment_id, event_type, payload) \
        \VALUES (?, ?, ?, ?, ?)"
        ( eventIdValue
        , gatewayName
        , paymentIdValue
        , eventTypeValue
        , payloadValue
        )

    pure ()

webhookEventExists
    :: Connection
    -> String
    -> IO Bool
webhookEventExists connection eventIdValue = do
    results <- query connection
        "SELECT event_id \
        \FROM webhook_events \
        \WHERE event_id = ?"
        (Only eventIdValue)
        :: IO [Only String]

    pure (not (null results))

markWebhookProcessed
    :: Connection
    -> String
    -> IO Bool
markWebhookProcessed connection eventIdValue = do
    affectedRows <- execute connection
        "UPDATE webhook_events \
        \SET processed = TRUE \
        \WHERE event_id = ?"
        (Only eventIdValue)

    pure (affectedRows == 1)

getPayment :: Connection -> String -> IO (Maybe Payment)
getPayment connection requestedId = do
    results <- query connection
        "SELECT payment_id, amount, currency, payment_method, status \
        \FROM payments WHERE payment_id = ?"
        (Only requestedId)

    pure (case results of
        [] -> Nothing
        row : _ -> Just (paymentFromRow row)
        )

paymentFromRow :: (String, Int, String, String, String) -> Payment
paymentFromRow (pid, paymentAmount, paymentCurrency, method, paymentStatus) =
    Payment
        { paymentId = pid
        , amount = paymentAmount
        , currency = paymentCurrency
        , paymentMethod = method
        , status = parseStatus paymentStatus
        }

parseStatus :: String -> PaymentStatus
parseStatus "Created" = Created
parseStatus "Processing" = Processing
parseStatus "Success" = Success
parseStatus "Failed" = Failed
parseStatus "Pending" = Pending
parseStatus "Captured" = Captured
parseStatus "Refunded" = Refunded
parseStatus _ = Created

getPaymentIdByIdempotencyKey :: Connection -> String -> IO (Maybe String)
getPaymentIdByIdempotencyKey connection key = do
    results <- query connection
        "SELECT payment_id \
        \FROM idempotency_keys \
        \WHERE idempotency_key = ?"
        (Only key)

    pure (case results of
        [] -> Nothing
        (Only paymentIdValue) : _ -> Just paymentIdValue
        )

saveIdempotencyKey :: Connection -> String -> String -> IO ()
saveIdempotencyKey connection key paymentIdValue = do
    _ <- execute connection
        "INSERT INTO idempotency_keys \
        \(idempotency_key, payment_id) \
        \VALUES (?, ?)"
        (key, paymentIdValue)

    pure ()
updatePaymentStatus :: Connection -> String -> PaymentStatus -> IO Bool
updatePaymentStatus connection requestedId newStatus = do
    affectedRows <- execute connection
        "UPDATE payments \
        \SET status = ? \
        \WHERE payment_id = ?"
        (show newStatus, requestedId)

    pure (affectedRows == 1)

capturePaymentAtomic
    :: Connection
    -> String
    -> IO Bool
capturePaymentAtomic connection requestedId = do
    affectedRows <- execute connection
        "UPDATE payments \
        \SET status = 'Captured' \
        \WHERE payment_id = ? \
        \AND status = 'Success'"
        (Only requestedId)

    pure (affectedRows == 1)


refundPaymentAtomic
    :: Connection
    -> String
    -> IO Bool
refundPaymentAtomic connection requestedId = do
    affectedRows <- execute connection
        "UPDATE payments \
        \SET status = 'Refunded' \
        \WHERE payment_id = ? \
        \AND status = 'Captured'"
        (Only requestedId)

    pure (affectedRows == 1)

savePaymentAttempt
    :: Connection
    -> String
    -> String
    -> String
    -> Maybe String
    -> IO ()
savePaymentAttempt connection paymentIdValue gatewayName attemptStatus errorCode = do
    _ <- execute connection
        "INSERT INTO payment_attempts \
        \(payment_id, gateway, status, error_code) \
        \VALUES (?, ?, ?, ?)"
        (paymentIdValue, gatewayName, attemptStatus, errorCode)

    pure ()

getRoutingRules
    :: Connection
    -> String
    -> String
    -> IO [(String, Int)]
getRoutingRules connection paymentCurrency paymentMethodValue = do
    query connection
        "SELECT gateway, priority \
        \FROM routing_rules \
        \WHERE currency = ? \
        \AND payment_method = ? \
        \AND enabled = TRUE \
        \ORDER BY priority ASC"
        (paymentCurrency, paymentMethodValue)
getGatewayHealth
    :: Connection
    -> String
    -> IO (Maybe (Bool, Double, String))
getGatewayHealth connection gatewayName = do
    results <- query connection
        "SELECT enabled, success_rate, circuit_state \
        \FROM gateway_health \
        \WHERE gateway = ?"
        (Only gatewayName)

    pure (case results of
        [] -> Nothing
        (enabledValue, successRateValue, circuitStateValue) : _ ->
            Just
                ( enabledValue
                , successRateValue
                , circuitStateValue
                )
        )
updateGatewayHealth
    :: Connection
    -> String
    -> Bool
    -> IO ()
updateGatewayHealth connection gatewayName succeeded = do
    _ <- execute connection
        "UPDATE gateway_health \
        \SET success_count = success_count + CASE WHEN ? THEN 1 ELSE 0 END, \
        \    failure_count = failure_count + CASE WHEN ? THEN 0 ELSE 1 END, \
        \    success_rate = \
        \        CASE \
        \            WHEN (success_count + failure_count + 1) = 0 THEN 100.0 \
        \            ELSE \
        \                ((success_count + CASE WHEN ? THEN 1 ELSE 0 END) * 100.0) \
        \                / (success_count + failure_count + 1) \
        \        END, \
        \    updated_at = NOW() \
        \WHERE gateway = ?"
        (succeeded, succeeded, succeeded, gatewayName)

    pure ()
recordGatewaySuccess
    :: Connection
    -> String
    -> IO ()
recordGatewaySuccess connection gatewayName = do
    _ <- execute connection
        "UPDATE gateway_health \
        \SET success_count = success_count + 1, \
        \    consecutive_failures = 0, \
        \    circuit_state = 'CLOSED', \
        \    opened_at = NULL, \
        \    success_rate = \
        \        (success_count + 1) * 100.0 \
        \        / (success_count + failure_count + 1), \
        \    updated_at = NOW() \
        \WHERE gateway = ?"
        (Only gatewayName)

    pure ()
tryHalfOpen
    :: Connection
    -> String
    -> IO Bool
tryHalfOpen connection gatewayName = do
    updated <- execute connection
        "UPDATE gateway_health \
        \SET circuit_state = 'HALF_OPEN' \
        \WHERE gateway = ? \
        \AND circuit_state = 'OPEN' \
        \AND opened_at IS NOT NULL \
        \AND opened_at <= NOW() - INTERVAL '30 seconds'"
        (Only gatewayName)

    pure (updated > 0)

recordGatewayFailure
    :: Connection
    -> String
    -> IO ()
recordGatewayFailure connection gatewayName = do
    _ <- execute connection
        "UPDATE gateway_health \
        \SET failure_count = failure_count + 1, \
        \    consecutive_failures = consecutive_failures + 1, \
        \    circuit_state = \
        \        CASE \
        \            WHEN consecutive_failures + 1 >= 3 \
        \            THEN 'OPEN' \
        \            ELSE circuit_state \
        \        END, \
        \    opened_at = \
        \        CASE \
        \            WHEN consecutive_failures + 1 >= 3 \
        \            THEN NOW() \
        \            ELSE opened_at \
        \        END, \
        \    success_rate = \
        \        success_count * 100.0 \
        \        / NULLIF(success_count + failure_count + 1, 0), \
        \    updated_at = NOW() \
        \WHERE gateway = ?"
        (Only gatewayName)

    pure ()

saveReconciliationRecord
    :: Connection
    -> String
    -> String
    -> String
    -> String
    -> String
    -> Maybe String
    -> IO ()
saveReconciliationRecord
    connection
    paymentIdValue
    gatewayName
    gatewayStatusValue
    internalStatusValue
    reconciliationStatus
    detailsValue = do
    _ <- execute connection
        "INSERT INTO reconciliation_records \
        \(payment_id, gateway, gateway_status, internal_status, status, details) \
        \VALUES (?, ?, ?, ?, ?, ?)"
        ( paymentIdValue
        , gatewayName
        , gatewayStatusValue
        , internalStatusValue
        , reconciliationStatus
        , detailsValue
        )
    pure ()

getReconciliationRecords
    :: Connection
    -> String
    -> IO [(String, String, String, String, String, Maybe String)]
getReconciliationRecords connection requestedId = do
    query connection
        "SELECT gateway, gateway_status, internal_status, \
        \status, created_at::TEXT, details \
        \FROM reconciliation_records \
        \WHERE payment_id = ? \
        \ORDER BY reconciliation_id ASC"
        (Only requestedId)    
