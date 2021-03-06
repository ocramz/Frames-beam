# Frames-beam

[![Build Status](https://travis-ci.org/gagandeepb/Frames-beam.png)](https://travis-ci.org/gagandeepb/Frames-beam)

## Accessing Postgres in a data frame in Haskell

A library for accessing Postgres tables as in-memory data structures.

This library provides helpers for generating  types (at compile time) corresponding to a database schema  and 'canned queries' to execute against a database instance. Additionally, it provides utilities to convert plain Haskell records (i.e. the format of query results) to `vinyl` records (upon which the Frames library is based). Can be used for interactive exploration by loading all data in-memory at once (and converting to a data frame), and also in a constant memory streaming mode. 

## Usage Example 
In this example we assume there is a local Postgres instance with schema and rows given by the small DB-dump present in `data/users.sql`.

### A. Interactive Workflow Steps
1. **Bootstrap database schema:** In a new project, assume a file `Example.hs` is present in the `src` directory with the code below. You may of course change the string passed to `genBeamSchema` to match your database instance of interest.
```haskell
-- Example.hs 
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
module Example where

import qualified Data.Conduit.List        as CL
import qualified Data.Vinyl.Functor       as VF
import qualified Frames                   as F
import           Frames.SQL.Beam.Postgres



$(genBeamSchema "host=localhost dbname=shoppingcart1")
```

2. Next, execute `stack build` or `stack ghci`. This compilation step, if completed without any errors, will establish a connection to your database instance of interest, read its schema, generate corresponding Haskell types and put them in a module named `NewBeamSchema` in your `src` directory (the file creation step is also part of the compilation process).

3. Assuming step 2 worked fine for you and you were using the test DB-dump from the `data` folder you should now have a module with code matching that in the `test/NewBeamSchema.hs` file of this repository. In case you used some other database instance of your own, your generated module would look different.
Import this module into `Example`:

```haskell
-- Example.hs
-- Extensions elided
module Example where

import qualified Data.Conduit.List        as CL
import qualified Data.Vinyl.Functor       as VF
import qualified Frames                   as F
import           Frames.SQL.Beam.Postgres

import NewBeamSchema


$(genBeamSchema "host=localhost dbname=shoppingcart1")
```

4. Let's assume the table of interest is `Cart_usersT`. We want to pull rows from this table into a data frame to explore it interactively from `ghci`. Note that `beam` query results are lists of plain Haskell records whereas `Frames` requires a list of `vinyl` records. In order to make this conversion, we add the following two invokations of code-generating (Template-Haskell) functions to `Example`:

```haskell
-- Example.hs
-- rest of the module elided

import NewBeamSchema


$(genBeamSchema "host=localhost dbname=shoppingcart1")

deriveGeneric ''Cart_usersT
deriveVinyl ''Cart_usersT
```
...and build your project. This will add some additional code into the `Example` module. You can inspect this code by adding the appropriate compiler flags to your `.cabal` file.

5. **Querying the DB:**
In this step we will execute a `SELECT * FROM tbl WHERE...` query and convert the results to a data frame. Note that the table declaration (`_cart_users`) and the database declaration (`db`) are exported by the `NewBeamSchema` module. More importantly, these declarations are autogenerated at compile time, so in case new tables are added, the corresponding declarations are automatically available for use.

```haskell
-- Example.hs
connString :: ByteString
connString = "host=localhost dbname=shoppingcart1"

-- selects 'n' rows from the specified table in the db.
loadRows1 :: Int -> IO [(Cart_usersT Identity)]
loadRows1 n =
  withConnection connString $
    bulkSelectAllRows _cart_users db n

loadRows2 :: Int -> IO [(Cart_usersT Identity)]
loadRows2 n =
  withConnection connString $
    bulkSelectAllRowsWhere _cart_users db n (\c -> (_cart_usersFirst_name c) `like_` "J%")
```
Notice the lambda passed to `bulkSelectAllRowsWhere` in `loadRows2`. This is a 'filter lambda' that forms the `WHERE ...` part of the SQL query and is executed at the DB-level. We will see how to create our own 'filter lambdas' in another section below. For now, if we were to enter `ghci` by executing `stack ghci` after adding the above code:
```ghci
ghci>res1 <- loadRows1 5
ghci>:t res1
res1 :: [Cart_usersT Identity]
ghci>:t (map createRecId res1)
(map createRecId res1)
  :: [F.Rec
        VF.Identity
        '["_cart_usersEmail" F.:-> Text,
          "_cart_usersFirst_name" F.:-> Text,
          "_cart_usersLast_name" F.:-> Text,
          "_cart_usersIs_member" F.:-> Bool,
          "_cart_usersDays_in_queue" F.:-> Int]]
ghci>:t (F.toFrame $ map createRecId res1)
(F.toFrame $ map createRecId res1)
  :: F.Frame
       (F.Record
          '["_cart_usersEmail" F.:-> Text,
            "_cart_usersFirst_name" F.:-> Text,
            "_cart_usersLast_name" F.:-> Text,
            "_cart_usersIs_member" F.:-> Bool,
            "_cart_usersDays_in_queue" F.:-> Int])
ghci>myFrame = F.toFrame $ map createRecId res1
ghci>:set -XTypeApplications
ghci>:set -XTypeOperators
ghci>:set -XDataKinds
ghci>miniFrame = fmap (F.rcast @'["_cart_usersEmail" F.:-> Text, "_cart_usersDays_in_queue" F.:-> Int]) myFrame
ghci>mapM_ print miniFrame
{_cart_usersEmail :-> "james@example.com", _cart_usersDays_in_queue :-> 1}
{_cart_usersEmail :-> "betty@example.com", _cart_usersDays_in_queue :-> 42}
{_cart_usersEmail :-> "james@pallo.com", _cart_usersDays_in_queue :-> 1}
{_cart_usersEmail :-> "betty@sims.com", _cart_usersDays_in_queue :-> 42}
{_cart_usersEmail :-> "james@oreily.com", _cart_usersDays_in_queue :-> 1}
```
We could have used `loadRows2` in place of `loadRows1` in order to have the `WHERE ...` clause executed at the DB-level.
Note that in the above, once the query results are converted to a data frame, you're free to play with the frame in anyway, just like you would for a data frame created from a CSV.

### B. Streaming Workflow Steps

Once you're done working with a small subset of data, and would like to scale up your analysis by looking at a larger-subset-of/complete data, then it's time to look at writing your own `conduit` to process incoming rows from the DB.

1 - 4: Same as 'Interactive Workflow Steps'

5. **Writing your own streaming pipeline:**

Consider the following:
```haskell
streamRows :: IO ()
streamRows = do
  res <-  withConnection connString $
            streamingSelectAllPipeline' _cart_users db 1000 (\c -> (_cart_usersFirst_name c) `like_` "J%") $
              (CL.map (\record -> F.rcast @["_cart_usersEmail" F.:-> Text, "_cart_usersIs_member" F.:-> Bool] record))
  mapM_ print res
```
In the above, we select all rows from the specified table that match a certain pattern (`"J%"`), then the function `streamingSelectAllPipeline'` converts the query results to vinyl records inside a `conduit` and sends it downstream, where we can operate on its output. Here, specifically, we do a column subset of the output using `rcast`, and `CL.map` applies `rcast` to every incoming row and sends it downstream, where the result gets returned. We then print the list of `vinyl` records.

In order to write your own conduit, all you need to know is that internally the conduit flow is as follows:

```haskell
(\c -> runConduit $ c .| CL.map createRecId
                      .| recordProcessorConduit
                      .| CL.take nrows)
```
In the above, you supply the `recordProcessorConduit` to the `streamingSelectAllPipeline'` function which takes a `vinyl` record as input and sends it downstream to the `CL.take`. Note that in all functions in the `Frames.SQL.Beam.Postgres.Streaming` module, you need to specify the number of rows you want to return (this is an upper bound of sorts, the actual number of rows returned depends on the amount of data present in your database).

## A Note on 'Canned Queries' and 'Filter Lambdas'

There are three things needed to execute a canned query (`SELECT * FROM tbl WHERE ...`):
* `PostgresTable a b`: auto generated by BeamSchemaGen module
* `PostgresDB b`: auto generated by BeamSchemaGen module
* `PostgresFilterLambda a s`: The `WHERE...` clause. All filter lambdas are of the form:
```haskell
(\tbl -> (_fieldName tbl) `op` constant)
```
or
```haskell
(\tbl -> (_fieldName1 tbl) `op` (_fieldName2 tbl))
```
In the above `op` can be one of : [`==.`, `/=.`, `>.`, `<.`, `<=.`, `>=.`, `between_`, `like_`, `in_` ] (some of these are not be applicable to the second case). You may use `(&&.)` and `(||.)` to combine expressions inside the lambda. To see some actual examples of 'filter lambdas', check out `test/LibSpec.hs` in this repository.

## Background Reading:

* About `deriveGeneric` and `deriveVinyl`: [Deriving Vinyl Representation From Plain Haskell Records][generic-vinyl]
* [Frames tutorial][frames-tutorial]
* [Beam tutorial and user-guide][beam-indepth]


[generic-vinyl]: https://www.gagandeepbhatia.com/blog/deriving-vinyl-representation-from-plain-haskell-records/
[frames-tutorial]: http://acowley.github.io/Frames/
[beam-indepth]: https://tathougies.github.io/beam/