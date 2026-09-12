module Repository.RedisRepository
    ( connectRedis
    , enqueueJob
    , dequeueJob
    ) where

import qualified Database.Redis as Redis
import qualified Data.ByteString.Char8 as BS
import Data.List.NonEmpty (NonEmpty(..))
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

connectRedis :: IO Redis.Connection
connectRedis = do
    host <- getEnvOrDefault "PAYSWITCH_REDIS_HOST" "127.0.0.1"
    portString <- getEnvOrDefault "PAYSWITCH_REDIS_PORT" "6379"

    let port =
            fromIntegral
                (maybe 6379 id (readMaybe portString :: Maybe Int))

        connectInfo =
            Redis.defaultConnectInfo
                { Redis.connectAddr =
                    Redis.ConnectAddrHostPort
                        host
                        port
                }

    Redis.checkedConnect connectInfo

enqueueJob :: Redis.Connection -> String -> String -> IO Bool
enqueueJob connection queueName job = do
    result <- Redis.runRedis connection $
        Redis.lpush
            (BS.pack queueName)
            (BS.pack job :| [])

    case result of
        Left _ -> pure False
        Right _ -> pure True

dequeueJob :: Redis.Connection -> String -> IO (Maybe String)
dequeueJob connection queueName = do
    result <- Redis.runRedis connection $
        Redis.brpop
            (BS.pack queueName :| [])
            0

    case result of
        Left _ -> pure Nothing
        Right Nothing -> pure Nothing
        Right (Just (_, job)) ->
            pure (Just (BS.unpack job))

getEnvOrDefault :: String -> String -> IO String
getEnvOrDefault name defaultValue = do
    value <- lookupEnv name
    pure (maybe defaultValue id value)