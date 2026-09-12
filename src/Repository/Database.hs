module Repository.Database where

import Database.PostgreSQL.Simple
    ( Connection
    , ConnectInfo(..)
    , connect
    , defaultConnectInfo
    )
import System.Environment (lookupEnv)

createConnection :: IO Connection
createConnection = do
    host <- getEnvOrDefault "PAYSWITCH_DB_HOST" "127.0.0.1"
    port <- getEnvOrDefault "PAYSWITCH_DB_PORT" "5432"
    user <- getEnvOrDefault "PAYSWITCH_DB_USER" "payswitch"
    password <- getEnvOrDefault
        "PAYSWITCH_DB_PASSWORD"
        "payswitch_dev_password"
    database <- getEnvOrDefault
        "PAYSWITCH_DB_NAME"
        "payswitch"

    connect defaultConnectInfo
        { connectHost = host
        , connectPort = read port
        , connectUser = user
        , connectPassword = password
        , connectDatabase = database
        }

getEnvOrDefault :: String -> String -> IO String
getEnvOrDefault name defaultValue = do
    value <- lookupEnv name
    pure (maybe defaultValue id value)