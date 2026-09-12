module Monitoring.Metrics
( Metrics
    , newMetrics
    , incrementPaymentsTotal
    , incrementPaymentsSuccess
    , incrementPaymentsFailed
    , incrementGatewayFailures
    , incrementGatewayRetries
    , incrementReconciliationMatches
    , incrementReconciliationMismatches
    , getMetrics
    , MetricsResponse(..)
    , toMetricsResponse 
    ) where


import Control.Concurrent.STM
import Data.Aeson.Key (fromString)
import Data.Aeson


data Metrics = Metrics
    { paymentsTotal :: TVar Int
    , paymentsSuccess :: TVar Int
    , paymentsFailed :: TVar Int
    , gatewayFailures :: TVar Int
    , gatewayRetries :: TVar Int
    , reconciliationMatches :: TVar Int
    , reconciliationMismatches :: TVar Int
    }

newMetrics :: IO Metrics
newMetrics = atomically $ do
    total <- newTVar 0
    success <- newTVar 0
    failed <- newTVar 0
    failures <- newTVar 0
    retries <- newTVar 0
    matches <- newTVar 0
    mismatches <- newTVar 0

    pure Metrics
        { paymentsTotal = total
        , paymentsSuccess = success
        , paymentsFailed = failed
        , gatewayFailures = failures
        , gatewayRetries = retries
        , reconciliationMatches = matches
        , reconciliationMismatches = mismatches
        }

incrementPaymentsTotal :: Metrics -> IO ()
incrementPaymentsTotal metrics =
    increment (paymentsTotal metrics)

incrementPaymentsSuccess :: Metrics -> IO ()
incrementPaymentsSuccess metrics =
    increment (paymentsSuccess metrics)

incrementPaymentsFailed :: Metrics -> IO ()
incrementPaymentsFailed metrics =
    increment (paymentsFailed metrics)

incrementGatewayFailures :: Metrics -> IO ()
incrementGatewayFailures metrics =
    increment (gatewayFailures metrics)

incrementGatewayRetries :: Metrics -> IO ()
incrementGatewayRetries metrics =
    increment (gatewayRetries metrics)

incrementReconciliationMatches :: Metrics -> IO ()
incrementReconciliationMatches metrics =
    increment (reconciliationMatches metrics)

incrementReconciliationMismatches :: Metrics -> IO ()
incrementReconciliationMismatches metrics =
    increment (reconciliationMismatches metrics)

increment :: TVar Int -> IO ()
increment counter =
    atomically $
        modifyTVar' counter (+1)

getMetrics :: Metrics -> IO (Int, Int, Int, Int, Int, Int, Int)
getMetrics metrics =
    atomically $ do
        total <- readTVar (paymentsTotal metrics)
        success <- readTVar (paymentsSuccess metrics)
        failed <- readTVar (paymentsFailed metrics)
        failures <- readTVar (gatewayFailures metrics)
        retries <- readTVar (gatewayRetries metrics)
        matches <- readTVar (reconciliationMatches metrics)
        mismatches <- readTVar (reconciliationMismatches metrics)

        pure
            ( total
            , success
            , failed
            , failures
            , retries
            , matches
            , mismatches
            )

data MetricsResponse = MetricsResponse
    { metricsPaymentsTotal :: Int
    , metricsPaymentsSuccess :: Int
    , metricsPaymentsFailed :: Int
    , metricsGatewayFailures :: Int
    , metricsGatewayRetries :: Int
    , metricsReconciliationMatches :: Int
    , metricsReconciliationMismatches :: Int
    }

instance ToJSON MetricsResponse where
    toJSON metrics =
        object
            [ fromString "payments_total"
                .= metricsPaymentsTotal metrics
            , fromString "payments_success"
                .= metricsPaymentsSuccess metrics
            , fromString "payments_failed"
                .= metricsPaymentsFailed metrics
            , fromString "gateway_failures"
                .= metricsGatewayFailures metrics
            , fromString "gateway_retries"
                .= metricsGatewayRetries metrics
            , fromString "reconciliation_matches"
                .= metricsReconciliationMatches metrics
            , fromString "reconciliation_mismatches"
                .= metricsReconciliationMismatches metrics
            ]

toMetricsResponse :: Metrics -> IO MetricsResponse
toMetricsResponse metrics = do
    (total, success, failed, failures, retries, matches, mismatches) <-
        getMetrics metrics

    pure MetricsResponse
        { metricsPaymentsTotal = total
        , metricsPaymentsSuccess = success
        , metricsPaymentsFailed = failed
        , metricsGatewayFailures = failures
        , metricsGatewayRetries = retries
        , metricsReconciliationMatches = matches
        , metricsReconciliationMismatches = mismatches
        }
