{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE OverloadedStrings      #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}
module LibSpec where

import           Test.Hspec
import           Test.Hspec.Core.Util

import qualified Data.Conduit.List        as CL
import qualified Data.Vinyl.Functor       as VF
import qualified Frames                   as F
import           Frames.SQL.Beam.Postgres
import           GHC.Exception            (SomeException)
import           NewBeamSchema



$(genBeamSchemaForTests "host=localhost dbname=shoppingcart1")

deriveGeneric ''Cart_usersT

deriveVinyl ''Cart_usersT

main :: IO ()
main = hspec spec

spec :: Spec
spec =
  describe "Integration Tests (Requires DB environment)" $ do
    it "test0" $ do
      res <- safeTry $ test0
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream1" $ do
      res <- safeTry $ testStream1 2
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream2" $ do
      res <- safeTry $ testStream2 2
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream3" $ do
      res <- safeTry $ testStream3 2
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream4" $ do
      res <- safeTry $ testStream4
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream5" $ do
      res <- safeTry $ testStream5
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream6" $ do
      res <- safeTry $ testStream6
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream7" $ do
      res <- safeTry $ testStream7
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream8" $ do
      res <- safeTry $ testStream8
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream9" $ do
      res <- safeTry $ testStream9
      (formatEx res) `shouldBe` (NoExceptionRaised)
    it "testStream10" $ do
      res <- safeTry $ testStream10
      (formatEx res) `shouldBe` (NoExceptionRaised)

data ExceptionStatus = ExceptionRaised String | NoExceptionRaised deriving (Show, Eq)

formatEx :: Either SomeException b -> ExceptionStatus
formatEx (Left e)  = ExceptionRaised (formatException e)
formatEx (Right _) = NoExceptionRaised

connString :: ByteString
connString = "host=localhost dbname=shoppingcart1"

test0 :: IO ()
test0 = do
  res <- testStream1 5
  mapM_ print $ F.toFrame $ map createRecId res

testStream1 :: Int -> IO [(Cart_usersT Identity)]
testStream1 n =
  withConnection connString $
    bulkSelectAllRows _cart_users db n


testStream2 :: Int -> IO ()
testStream2 n = do
  res <- testStream3 n
  mapM_ print $ map createRecId  res


testStream3 :: Int -> IO [(Cart_usersT Identity)]
testStream3 n =
  withConnection connString $
    bulkSelectAllRowsWhere _cart_users db n (\c -> (_cart_usersFirst_name c) `like_` "J%")



testStream4 :: IO ()
testStream4 = do
  res <-  testStream1 5
  mapM_ (print . createRecId) res


testStream5 :: IO ()
testStream5 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c -> (_cart_usersFirst_name c) `like_` "J%") $
              (CL.isolate 1000)
  mapM_ print res

-- Streaming column-subset
testStream6 :: IO ()
testStream6 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c -> (_cart_usersFirst_name c) `like_` "J%") $
              (CL.map (\record -> F.rcast @["_cart_usersEmail" F.:-> Text, "_cart_usersIs_member" F.:-> Bool] record))
  mapM_ print res


testStream7 :: IO ()
testStream7 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c ->
                (charLength_ $ _cart_usersFirst_name c) >. (charLength_ $ _cart_usersLast_name c)) $
              (CL.isolate 1000)
  mapM_ print res


testStream8 :: IO ()
testStream8 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c ->
                ((_cart_usersFirst_name c) `like_` "J%") &&.
                ((_cart_usersLast_name c) `like_` "S%") ) $
              (CL.isolate 1000)
  mapM_ print res


testStream9 :: IO ()
testStream9 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c ->
                ((_cart_usersFirst_name c) `like_` "J%") ||.
                ((_cart_usersDays_in_queue c) `in_` [1, 5, 10, 20, 30]) ) $
              (CL.isolate 1000)
  mapM_ print res


testStream10 :: IO ()
testStream10 = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c ->
                not_ ((_cart_usersFirst_name c) `like_` "J%") &&.
                ((_cart_usersDays_in_queue c) ==. 42) ) $
              (CL.isolate 1000)
  mapM_ print res
