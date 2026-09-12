module Worker.PaymentWorker
    ( runWorker
    ) where

import Control.Concurrent (threadDelay)
import qualified Database.Redis as Redis
import qualified Database.PostgreSQL.Simple
import qualified Repository.Database
import qualified Repository.RedisRepository as RedisRepository
import qualified Service.PaymentService as PaymentService

queueName :: String
queueName = "payswitch:jobs"

runWorker :: IO ()
runWorker = do
    putStrLn "PaySwitch background worker started"

    redisConnection <- RedisRepository.connectRedis
    databaseConnection <- Repository.Database.createConnection

    workerLoop redisConnection databaseConnection

workerLoop
    :: Redis.Connection
    -> Database.PostgreSQL.Simple.Connection
    -> IO ()
workerLoop redisConnection databaseConnection = do

    maybeJob <-
        RedisRepository.dequeueJob
            redisConnection
            queueName

    case maybeJob of
        Nothing -> do
            threadDelay 1000000
            workerLoop redisConnection databaseConnection

        Just job -> do
            putStrLn ("Processing job: " ++ job)

            processJob databaseConnection job

            workerLoop redisConnection databaseConnection

processJob
    :: Database.PostgreSQL.Simple.Connection
    -> String
    -> IO ()
processJob databaseConnection job =
    case parseReconciliationJob job of
        Nothing ->
            putStrLn ("Invalid job format: " ++ job)

        Just (paymentId, gateway, gatewayStatus) -> do
            result <-
                PaymentService.reconcilePayment
                    databaseConnection
                    paymentId
                    gateway
                    gatewayStatus

            case result of
                Left errorMessage ->
                    putStrLn
                        ("Reconciliation failed: " ++ errorMessage)

                Right reconciliationStatus ->
                    putStrLn
                        ( "Reconciliation completed: "
                            ++ paymentId
                            ++ " -> "
                            ++ reconciliationStatus
                        )

parseReconciliationJob
    :: String
    -> Maybe (String, String, String)
parseReconciliationJob job =
    case splitPipe job of
        [paymentId, gateway, gatewayStatus]
            | not (null paymentId)
            , not (null gateway)
            , not (null gatewayStatus) ->
                Just
                    ( paymentId
                    , gateway
                    , gatewayStatus
                    )

        _ -> Nothing

splitPipe :: String -> [String]
splitPipe [] = [""]
splitPipe input =
    let (part, rest) = break (== '|') input
    in case rest of
        [] -> [part]
        (_:remaining) -> part : splitPipe remaining
