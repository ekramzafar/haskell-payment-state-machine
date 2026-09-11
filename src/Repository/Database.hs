module Repository.Database where

import Database.PostgreSQL.Simple
    ( Connection
    , ConnectInfo(..)
    , connect
    , defaultConnectInfo
    )

createConnection :: IO Connection
createConnection =
    connect defaultConnectInfo
        { connectHost = "127.0.0.1"
        , connectPort = 5432
        , connectUser = "payswitch"
        , connectPassword = "payswitch_dev_password"
        , connectDatabase = "payswitch"
        }
