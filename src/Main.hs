{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE OverloadedStrings    #-}

module Main where

--

import           Control.Monad.Except
import           Data.Aeson ((.=))
import qualified Data.Aeson as A
import           Data.Conduit (runConduit, awaitForever, Source, (=$), ($$))
import qualified Data.ByteString.Lazy as BL
import qualified Data.HashMap.Lazy as HM
import           Network.HTTP.Client (newManager)
import           Network.HTTP.Client.TLS (tlsManagerSettings)

import           Azure.DocDB hiding (collection)
import           Paths_azure_docdb
import           Settings

{-
Database    https://{databaseaccount}.documents.azure.com/dbs/{db}
User 	      https://{databaseaccount}.documents.azure.com/dbs/{db}/users/{user}
Permission 	https://{databaseaccount}.documents.azure.com/dbs/{db}/users/{user}/permissions/{perm}
Collection 	https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}
SPROC  	    https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}/sprocs/{sproc}
Trigger 	  https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}/triggers/{trigger}
UDF 	      https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}/udfs/{udf}
Document 	  https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}/docs/{doc}
Attachment 	https://{databaseaccount}.documents.azure.com/dbs/{db}/colls/{coll}/docs/{doc}/attachments/{attch}
Offer 	    https://{databaseaccount}.documents.azure.com/offers/{offer}
-}


--
testGetDoc :: (MonadIO m, DBSocketMonad m) => CollectionId -> m ()
testGetDoc coll = do
  rslt :: Maybe (DBDocument A.Object) <- getDocument (pure (coll #> "testdoc"))
  liftIO $ print rslt


testDeleteDoc :: (MonadIO m, DBSocketMonad m) => DocumentId -> m ()
testDeleteDoc doc = deleteDocument (pure doc)


testCreateDoc :: (MonadIO m, DBSocketMonad m) => DocumentId -> m (DBDocument A.Value)
testCreateDoc (DocumentId coll docName) = do
  let testDoc = A.Object $ HM.fromList
                  [ ("id", A.String docName),
                    ("Hello", A.Number 98000) ]
  rslt2 :: DBDocument A.Value <- createDocument coll testDoc
  liftIO $ print rslt2
  return rslt2


testReplaceDoc :: (MonadIO m, DBSocketMonad m) => ETagged DocumentId -> m (DBDocument A.Value)
testReplaceDoc taggedId@(ETagged _ (DocumentId _ docName)) = do
  let testDoc3 = A.Object $ HM.fromList
                   [ ("id", A.String docName),
                     ("Hello", A.Number 1011) ]
  rslt2 :: DBDocument A.Value <- replaceDocument taggedId testDoc3
  liftIO $ print rslt2
  return rslt2


testListDocs :: (MonadIO m, DBSocketMonad m)
  => CollectionId
  -> m ()
testListDocs coll = runConduit $
  docList =$ awaitForever (liftIO . print)
  where
    docList :: DBSocketMonad m => Source m (DBDocument A.Value)
    docList = listAll $ listDocuments coll



testQueryDocs :: (MonadIO m, DBSocketMonad m)
  => CollectionId
  -> m ()
testQueryDocs coll = docList $$ awaitForever (liftIO . print)
  where
    docList :: DBSocketMonad m => Source m (DBDocument A.Value)
    docList = listAll $ queryDocuments dbQueryParamSimple coll sqlQuery

    sqlQuery = DBSQL "SELECT * FROM Docs d WHERE d.Hello = @h"
      ["@h" .= (1011 :: Int)]


test1 :: (MonadIO m, DBSocketMonad m) => CollectionId -> m ()
test1 coll = do
  sep "testGetDoc"
  testGetDoc coll
  sep "testDeleteDoc"
  safeRun $ testDeleteDoc doc
  sep "testCreateDoc"
  etaggedDoc <- testCreateDoc doc
  sep "testReplaceDoc"
  testReplaceDoc (ETagged (Just $ dbdETag etaggedDoc) doc)
  sep "query"
  testQueryDocs coll
  sep "testListDocs"
  testListDocs coll

  liftIO $ print "Done Tests"

  where
    doc = coll #> "myTestDoc"
    sep name = liftIO $ do
      putStrLn $ replicate 20 '-'
      putStrLn name
      putStrLn ""


safeRun :: (Show a, MonadIO m, MonadError a m) => m () -> m ()
safeRun m = catchError m (
  liftIO . (putStrLn "ERROR CATCH!" *>) . print
  )


main :: IO ()
main = do
  s <- BL.readFile =<< getDataFileName "settings.js"
  settings <- either (fail "No cfg") return (A.eitherDecode s :: Either String Settings)
  let pwd = fromBase64 . secondary . auth $ settings
  let testCollection = db settings #> collection settings

  --
  manager <- newManager tlsManagerSettings
  state <- mkDBSocketState pwd ("https://" `mappend` accountEndpoint settings) manager

  execDBSocketT
    (evalDBSessionT (safeRun $ test1 testCollection))
    state

  print "done"
