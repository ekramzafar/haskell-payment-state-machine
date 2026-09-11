module Main where

import Domain.Payment
import Service.PaymentService
import System.Exit (exitFailure, exitSuccess)

assert :: String -> Bool -> IO ()
assert name condition =
    if condition
        then putStrLn ("PASS: " ++ name)
        else do
            putStrLn ("FAIL: " ++ name)
            exitFailure

main :: IO ()
main = do
    putStrLn "Running PaySwitch tests..."
    putStrLn ""

    -- Payment validation
    assert
        "valid payment"
        (validatePayment
            (CreatePaymentRequest 100000 "INR" "card")
            == Right ())

    assert
        "reject zero amount"
        (validatePayment
            (CreatePaymentRequest 0 "INR" "card")
            == Left "Amount must be greater than zero")

    assert
        "reject negative amount"
        (validatePayment
            (CreatePaymentRequest (-100) "INR" "card")
            == Left "Amount must be greater than zero")

    assert
        "reject missing currency"
        (validatePayment
            (CreatePaymentRequest 100000 "" "card")
            == Left "Currency is required")

    assert
        "reject missing payment method"
        (validatePayment
            (CreatePaymentRequest 100000 "INR" "")
            == Left "Payment method is required")

    -- Payment state machine
    assert
        "Created -> Processing"
        (isValidTransition Created Processing)

    assert
        "Processing -> Success"
        (isValidTransition Processing Success)

    assert
        "Processing -> Failed"
        (isValidTransition Processing Failed)

    assert
        "Success -> Captured"
        (isValidTransition Success Captured)

    assert
        "Captured -> Refunded"
        (isValidTransition Captured Refunded)

    assert
        "Created -> Success rejected"
        (not (isValidTransition Created Success))

    assert
        "Success -> Refunded rejected"
        (not (isValidTransition Success Refunded))

    assert
        "Captured -> Success rejected"
        (not (isValidTransition Captured Success))

    assert
        "Refunded -> Captured rejected"
        (not (isValidTransition Refunded Captured))

    putStrLn ""
    putStrLn "All PaySwitch tests passed!"
    exitSuccess
