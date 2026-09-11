{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Payment where

import Data.Aeson
    ( FromJSON(..)
    , ToJSON(..)
    , object
    , withObject
    , (.:)
    , (.=)
    )
import GHC.Generics (Generic)

data PaymentStatus
    = Created
    | Processing
    | Success
    | Failed
    | Pending
    | Captured
    | Refunded
    deriving (Show, Eq, Generic)

instance ToJSON PaymentStatus
instance FromJSON PaymentStatus

data CreatePaymentRequest = CreatePaymentRequest
    { requestAmount        :: Int
    , requestCurrency      :: String
    , requestPaymentMethod :: String
    }
    deriving (Show, Eq, Generic)

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
    deriving (Show, Eq, Generic)

instance ToJSON Payment
instance FromJSON Payment