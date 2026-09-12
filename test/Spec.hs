module Main where

import Test.Hspec
import Domain.Payment
import Gateway.Gateway
import Service.PaymentService
    ( validatePayment
    , isValidTransition
    )
import Service.PaymentRouter
    ( GatewayCandidate(..)
    , isRetryable
    , gatewayErrorMessage
    , sortByPriority
    )

main :: IO ()
main = hspec $ do

    describe "Payment validation" $ do

        it "accepts a valid payment request" $ do
            let request =
                    CreatePaymentRequest
                        { requestAmount = 10000
                        , requestCurrency = "INR"
                        , requestPaymentMethod = "card"
                        }

            validatePayment request `shouldBe` Right ()

        it "rejects zero amount" $ do
            let request =
                    CreatePaymentRequest
                        { requestAmount = 0
                        , requestCurrency = "INR"
                        , requestPaymentMethod = "card"
                        }

            validatePayment request `shouldSatisfy` isLeft

        it "rejects negative amount" $ do
            let request =
                    CreatePaymentRequest
                        { requestAmount = -100
                        , requestCurrency = "INR"
                        , requestPaymentMethod = "card"
                        }

            validatePayment request `shouldSatisfy` isLeft

        it "rejects empty currency" $ do
            let request =
                    CreatePaymentRequest
                        { requestAmount = 10000
                        , requestCurrency = ""
                        , requestPaymentMethod = "card"
                        }

            validatePayment request `shouldSatisfy` isLeft

        it "rejects empty payment method" $ do
            let request =
                    CreatePaymentRequest
                        { requestAmount = 10000
                        , requestCurrency = "INR"
                        , requestPaymentMethod = ""
                        }

            validatePayment request `shouldSatisfy` isLeft


    describe "Payment state machine" $ do

        it "allows CREATED -> PROCESSING" $ do
            isValidTransition Created Processing
                `shouldBe` True

        it "allows PROCESSING -> SUCCESS" $ do
            isValidTransition Processing Success
                `shouldBe` True

        it "allows PROCESSING -> FAILED" $ do
            isValidTransition Processing Failed
                `shouldBe` True

        it "allows SUCCESS -> CAPTURED" $ do
            isValidTransition Success Captured
                `shouldBe` True

        it "allows CAPTURED -> REFUNDED" $ do
            isValidTransition Captured Refunded
                `shouldBe` True

        it "rejects CREATED -> SUCCESS" $ do
            isValidTransition Created Success
                `shouldBe` False

        it "rejects SUCCESS -> PROCESSING" $ do
            isValidTransition Success Processing
                `shouldBe` False

        it "rejects FAILED -> SUCCESS" $ do
            isValidTransition Failed Success
                `shouldBe` False

        it "rejects REFUNDED -> CAPTURED" $ do
            isValidTransition Refunded Captured
                `shouldBe` False

        it "rejects staying in the same state" $ do
            isValidTransition Created Created
                `shouldBe` False


    describe "Gateway retry policy" $ do

        it "treats gateway timeout as retryable" $ do
            isRetryable GatewayTimeout
                `shouldBe` True

        it "treats gateway unavailable as retryable" $ do
            isRetryable GatewayUnavailable
                `shouldBe` True

        it "does not retry payment declined" $ do
            isRetryable PaymentDeclined
                `shouldBe` False

        it "does not retry insufficient funds" $ do
            isRetryable InsufficientFunds
                `shouldBe` False

        it "does not retry invalid payment method" $ do
            isRetryable InvalidPaymentMethod
                `shouldBe` False


    describe "Gateway error messages" $ do

        it "maps timeout to a readable message" $ do
            gatewayErrorMessage GatewayTimeout
                `shouldBe` "Gateway timeout"

        it "maps unavailable to a readable message" $ do
            gatewayErrorMessage GatewayUnavailable
                `shouldBe` "Gateway unavailable"

        it "maps declined to a readable message" $ do
            gatewayErrorMessage PaymentDeclined
                `shouldBe` "Payment declined"

        it "maps insufficient funds to a readable message" $ do
            gatewayErrorMessage InsufficientFunds
                `shouldBe` "Insufficient funds"

        it "maps invalid payment method to a readable message" $ do
            gatewayErrorMessage InvalidPaymentMethod
                `shouldBe` "Invalid payment method"


    describe "Gateway routing priority" $ do

        it "sorts gateways from highest priority to lowest priority" $ do
            let candidates =
                    [ GatewayCandidate "Gateway-A" 3 ()
                    , GatewayCandidate "Gateway-B" 1 ()
                    , GatewayCandidate "Gateway-C" 2 ()
                    ]

                sorted = sortByPriority candidates

            map candidateName sorted
                `shouldBe`
                [ "Gateway-B"
                , "Gateway-C"
                , "Gateway-A"
                ]

        it "keeps a single gateway unchanged" $ do
            let candidates =
                    [ GatewayCandidate "Gateway-A" 1 ()
                    ]

            map candidateName (sortByPriority candidates)
                `shouldBe`
                [ "Gateway-A"
                ]

        it "handles an empty gateway list" $ do
            map candidateName (sortByPriority ([] :: [GatewayCandidate ()]))
                `shouldBe`
                []

        it "orders equal-priority gateways consistently" $ do
            let candidates =
                    [ GatewayCandidate "Gateway-A" 2 ()
                    , GatewayCandidate "Gateway-B" 1 ()
                    , GatewayCandidate "Gateway-C" 2 ()
                    ]

                sorted = sortByPriority candidates

            map candidateName sorted
                `shouldBe`
                [ "Gateway-B"
                , "Gateway-A"
                , "Gateway-C"
                ]


    describe "Payment status values" $ do

        it "contains all supported payment states" $ do
            map show
                [ Created
                , Processing
                , Success
                , Failed
                , Pending
                , Captured
                , Refunded
                ]
                `shouldBe`
                [ "Created"
                , "Processing"
                , "Success"
                , "Failed"
                , "Pending"
                , "Captured"
                , "Refunded"
                ]


isLeft :: Either a b -> Bool
isLeft result =
    case result of
        Left _ -> True
        Right _ -> False
