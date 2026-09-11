module Service.PaymentService where

import Domain.Payment
import Database.PostgreSQL.Simple (Connection)
import qualified Repository.PaymentRepository as PaymentRepository
import Service.PaymentRouter
import Gateway.Gateway

validatePayment :: CreatePaymentRequest -> Either String ()
validatePayment request
    | requestAmount request <= 0 =
        Left "Amount must be greater than zero"

    | requestCurrency request == "" =
        Left "Currency is required"

    | requestPaymentMethod request == "" =
        Left "Payment method is required"

    | otherwise =
        Right ()

createPayment
    :: Gateway gateway
    => Connection
    -> [GatewayCandidate gateway]
    -> CreatePaymentRequest
    -> String
    -> IO (Either String Payment)
createPayment connection gateways request paymentId =
    case validatePayment request of
        Left errorMessage ->
            pure (Left errorMessage)

        Right () -> do
            let payment = Payment
                    { paymentId = paymentId
                    , amount = requestAmount request
                    , currency = requestCurrency request
                    , paymentMethod = requestPaymentMethod request
                    , status = Created
                    }

            PaymentRepository.savePayment
                connection
                payment

            PaymentRepository.savePaymentEvent
                connection
                paymentId
                "payment_created"
                Nothing
                Nothing

            processingUpdated <- PaymentRepository.updatePaymentStatus
                connection
                paymentId
                Processing

            if not processingUpdated
                then do
                    PaymentRepository.savePaymentEvent
                        connection
                        paymentId
                        "payment_processing_failed"
                        Nothing
                        (Just "Failed to start payment processing")

                    pure (Left "Failed to start payment processing")

                else do
                    PaymentRepository.savePaymentEvent
                        connection
                        paymentId
                        "payment_processing"
                        Nothing
                        Nothing

                    let processingPayment =
                            payment
                                { status = Processing }

                    result <- routePayment
                        connection
                        processingPayment
                        gateways

                    case result of
                        Left errorMessage -> do
                            _ <- PaymentRepository.updatePaymentStatus
                                connection
                                paymentId
                                Failed

                            PaymentRepository.savePaymentEvent
                                connection
                                paymentId
                                "payment_failed"
                                Nothing
                                (Just errorMessage)

                            pure (Left errorMessage)

                        Right _ -> do
                            successUpdated <- PaymentRepository.updatePaymentStatus
                                connection
                                paymentId
                                Success

                            if successUpdated
                                then do
                                    PaymentRepository.savePaymentEvent
                                        connection
                                        paymentId
                                        "payment_success"
                                        Nothing
                                        Nothing

                                    pure
                                        (Right processingPayment
                                            { status = Success }
                                        )

                                else
                                    pure
                                        (Left "Failed to mark payment as successful")



capturePayment
    :: Connection
    -> String
    -> IO (Either String Payment)
capturePayment connection requestedId = do
    existingPayment <- PaymentRepository.getPayment
        connection
        requestedId

    case existingPayment of
        Nothing ->
            pure (Left "Payment not found")

        Just payment ->
            case status payment of
                Success -> do
                    updated <- PaymentRepository.capturePaymentAtomic
                        connection
                        requestedId

                    if updated
                        then do
                            PaymentRepository.savePaymentEvent
                                connection
                                requestedId
                                "payment_captured"
                                Nothing
                                Nothing

                            pure
                                (Right payment
                                    { status = Captured }
                                )

                        else
                            pure
                                (Left "Failed to capture payment")

                _ ->
                    pure
                        (Left "Payment must be in Success state before capture")

refundPayment
    :: Connection
    -> String
    -> IO (Either String Payment)
refundPayment connection requestedId = do
    existingPayment <- PaymentRepository.getPayment
        connection
        requestedId

    case existingPayment of
        Nothing ->
            pure (Left "Payment not found")

        Just payment ->
            case status payment of
                Captured -> do
                    updated <- PaymentRepository.refundPaymentAtomic
                        connection
                        requestedId

                    if updated
                        then do
                            PaymentRepository.savePaymentEvent
                                connection
                                requestedId
                                "payment_refunded"
                                Nothing
                                Nothing

                            pure
                                (Right payment
                                    { status = Refunded }
                                )

                        else
                            pure
                                (Left "Failed to refund payment")

                _ ->
                    pure
                        (Left "Payment must be in Captured state before refund")

updatePaymentStatus
    :: Connection
    -> String
    -> PaymentStatus
    -> IO (Either String Payment)
updatePaymentStatus connection requestedId newStatus = do
    existingPayment <- PaymentRepository.getPayment
        connection
        requestedId

    case existingPayment of
        Nothing ->
            pure (Left "Payment not found")

        Just payment ->
            if isValidTransition (status payment) newStatus
                then do
                    updated <- PaymentRepository.updatePaymentStatus
                        connection
                        requestedId
                        newStatus

                    if updated
                        then do
                            PaymentRepository.savePaymentEvent
                                connection
                                requestedId
                                ("payment_status_" ++ show newStatus)
                                Nothing
                                Nothing

                            pure
                                (Right payment
                                    { status = newStatus }
                                )

                        else
                            pure
                                (Left "Failed to update payment")

                else
                    pure
                        (Left "Invalid payment status transition")


isValidTransition :: PaymentStatus -> PaymentStatus -> Bool
isValidTransition Created Processing = True
isValidTransition Processing Success = True
isValidTransition Processing Failed = True
isValidTransition Success Captured = True
isValidTransition Captured Refunded = True
isValidTransition _ _ = False


reconcilePayment
    :: Connection
    -> String
    -> String
    -> String
    -> IO (Either String String)
reconcilePayment connection requestedId gatewayName gatewayStatus = do
    existingPayment <- PaymentRepository.getPayment connection requestedId

    case existingPayment of
        Nothing ->
            pure (Left "Payment not found")

        Just payment -> do
            let internalStatus = show (status payment)

            let reconciliationStatus =
                    if gatewayStatus == internalStatus
                        then "MATCH"
                        else "MISMATCH"

            let details =
                    if reconciliationStatus == "MATCH"
                        then Nothing
                        else Just
                            ( "Gateway reported "
                              ++ gatewayStatus
                              ++ " but internal system has "
                              ++ internalStatus
                            )

            PaymentRepository.saveReconciliationRecord
                connection
                requestedId
                gatewayName
                gatewayStatus
                internalStatus
                reconciliationStatus
                details

            PaymentRepository.savePaymentEvent
                connection
                requestedId
                "payment_reconciled"
                (Just gatewayName)
                (Just reconciliationStatus)

            pure (Right reconciliationStatus)