{-#LANGUAGE DeriveGeneric  #-}
{-#LANGUAGE DeriveAnyClass #-}
{-#LANGUAGE RecordWildCards #-}

module Main where

import GHC.Generics
import Data.Binary

import Control.Distributed.Process
import qualified Control.Distributed.Process.Node as N
import Control.Distributed.Process.Backend.SimpleLocalnet
import System.Environment (getArgs)
import System.Random.MWC
import Control.Concurrent
import Process

import Data.List



main :: IO ()
main = do
    [role, host,port] <- getArgs
    backend <- initializeBackend host port N.initRemoteTable 
    localNode <- newLocalNode backend
    gen <- create
    case role of 
       "rng"    -> N.runProcess localNode (initSupervisor 3 2 (Just gen) backend)   
       "normal" -> N.runProcess localNode (initSupervisor 3 2 (Nothing) backend)   
       _      -> return ()
