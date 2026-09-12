{-# LANGUAGE OverloadedStrings #-}

module Domain.Payment where

import Data.Aeson
    ( FromJSON(..)
    , ToJSON(..)
    , object
    , withObject
    , withText
    , (.:)
    , (.=)
    )

data PaymentStatus
    = Created
    | Processing
    | Success
    | Failed
    | Pending
    | Captured
    | Refunded
    deriving (Show, Eq)

instance ToJSON PaymentStatus where
    toJSON Created = "Created"
    toJSON Processing = "Processing"
    toJSON Success = "Success"
    toJSON Failed = "Failed"
    toJSON Pending = "Pending"
    toJSON Captured = "Captured"
    toJSON Refunded = "Refunded"

instance FromJSON PaymentStatus where
    parseJSON =
        withText "PaymentStatus" $ \value ->
            case value of
                "Created" -> pure Created
                "Processing" -> pure Processing
                "Success" -> pure Success
                "Failed" -> pure Failed
                "Pending" -> pure Pending
                "Captured" -> pure Captured
                "Refunded" -> pure Refunded
                _ -> fail "Invalid payment status"

data CreatePaymentRequest = CreatePaymentRequest
    { requestAmount        :: Int
    , requestCurrency      :: String
    , requestPaymentMethod :: String
    }
    deriving (Show, Eq)

instance ToJSON CreatePaymentRequest where
    toJSON request =
        object
            [ "amount" .= requestAmount request
            , "currency" .= requestCurrency request
            , "paymentMethod" .= requestPaymentMethod request
            ]

instance FromJSON CreatePaymentRequest where
    parseJSON = withObject "CreatePaymentRequest" $ \obj ->
        CreatePaymentRequest
            <$> obj .: "amount"
            <*> obj .: "currency"
            <*> obj .: "paymentMethod"

data Payment = Payment
    { paymentId     :: String
    , amount        :: Int
    , currency      :: String
    , paymentMethod :: String
    , status        :: PaymentStatus
    }
    deriving (Show, Eq)

instance ToJSON Payment where
    toJSON payment =
        object
            [ "paymentId" .= paymentId payment
            , "amount" .= amount payment
            , "currency" .= currency payment
            , "paymentMethod" .= paymentMethod payment
            , "status" .= status payment
            ]

instance FromJSON Payment where
    parseJSON = withObject "Payment" $ \obj ->
        Payment
            <$> obj .: "paymentId"
            <*> obj .: "amount"
            <*> obj .: "currency"
            <*> obj .: "paymentMethod"
            <*> obj .: "status"