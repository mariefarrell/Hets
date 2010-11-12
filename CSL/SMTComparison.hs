{- |
Module      :  $Header$
Description :  SMT interface for set comparison
Copyright   :  (c) Ewaryst Schulz, DFKI Bremen 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  ewaryst.schulz@dfki.de
Stability   :  experimental
Portability :  portable

This module defines an interface to the SMT solver yices for solving comparison
requests for integer sets defined by the usual boolean operations on the usual
comparison predicates.

The yices input is generated by producing input text files in yices format,
see http://yices.csl.sri.com/language.shtml for the syntax description.

There is also the yices-easy hackage entry which uses the C-API of yices.
This could be an alternative if speed and robustness will be a problem.
-}

module CSL.SMTComparison where


import Control.Monad
import qualified Data.Map as Map
import Data.List
import System.Process
import System.IO.Unsafe

import CSL.TreePO
import CSL.EPBasic

-- ----------------------------------------------------------------------
-- * SMT output generation for SMT based comparison
-- ----------------------------------------------------------------------

-- | This maps are assumed to have distinct values in [1..Map.size varmap],
-- i.e., v::VarMap => Set.fromList (Map.elems v) = {1..Map.size v}
type VarMap = Map.Map String Int

type VarTypes = Map.Map String (Maybe BoolRep)

data VarEnv = VarEnv { varmap :: VarMap
                     , vartypes :: VarTypes }

-- | Type alias and subtype definitions for the domain of the extended params
smtTypeDef :: VarEnv -> String
smtTypeDef m = Map.foldWithKey f "" $ vartypes m
    where err = error "smtTypeDef: No matching"
          lu s = show $ Map.findWithDefault err s $ varmap m
          g k a = case a of
                    Just br ->
                        concat [ "(define-type t", lu k, " (subtype (x"
                               , lu k, "::int) ", smtBoolExp br, "))" ]
                    Nothing ->
                        concat [ "(define-type t", lu k, " int)" ]
          f k a s = s ++ g k a ++ "\n"

-- | Predicate definition
smtPredDef :: VarEnv -> String -> BoolRep -> String
smtPredDef m s b = concat [ "(define ", s, "::(->"
                          , concat $ smtVars m " t"
                          , " bool) (lambda ("
                          , concat $ smtGenericVars m
                                       (\ i -> let j = show i
                                               in concat [" x", j, "::t", j])
                          , ") ", smtBoolExp b, "))" ]

smtVarDef :: VarEnv -> String
smtVarDef m =
    unlines
    $ smtGenericVars m (\ i -> let j = show i
                               in concat ["(define y", j, "::t", j, ")"])

smtVars :: VarEnv -> String -> [String]
smtVars m s = smtGenericVars m ((s++) . show)

smtGenericVars :: VarEnv -> (Int -> a) -> [a]
smtGenericVars m f = map f [1 .. Map.size $ varmap m]

smtGenericStmt :: VarEnv -> String -> String -> String -> String
smtGenericStmt m s a b =
    let vl = concat $ map (" "++) $ smtVars m "y"
    in concat ["(assert+ (not (", s, " (", a, vl, ") (", b, vl, "))))"]

smtEQStmt :: VarEnv -> String -> String -> String
smtEQStmt m a b = smtGenericStmt m "=" a b

smtLEStmt :: VarEnv -> String -> String -> String
smtLEStmt m a b = smtGenericStmt m "=>" a b

smtDisjStmt :: VarEnv -> String -> String -> String
smtDisjStmt m a b = 
    let vl = concat $ map (" "++) $ smtVars m "y"
    in concat ["(assert+ (and (", a, vl, ") (", b, vl, ")))"]


smtAllScript :: VarEnv -> BoolRep -> BoolRep -> String
smtAllScript m r1 r2 =
    unlines [ smtScriptHead m r1 r2
            , smtEQStmt m "A" "B", "(check) (retract 1)"
            , smtLEStmt m "A" "B", "(check) (retract 2)"
            , smtLEStmt m "B" "A", "(check) (retract 3)"
            , smtDisjStmt m "A" "B", "(check)" ]


smtAllScripts :: VarEnv -> BoolRep -> BoolRep -> [String]
smtAllScripts m r1 r2 =
    let h = smtScriptHead m r1 r2
    in [ unlines [h, smtEQStmt m "A" "B", "(check)"]
       , unlines [h, smtLEStmt m "A" "B", "(check)"]
       , unlines [h, smtLEStmt m "B" "A", "(check)"]
       , unlines [h, smtDisjStmt m "A" "B", "(check)"]
       ]

smtScriptHead :: VarEnv -> BoolRep -> BoolRep -> String
smtScriptHead m r1 r2 = unlines [ -- "(set-arith-only! true)"
                                  smtTypeDef m
                                , smtPredDef m "A" r1
                                , smtPredDef m "B" r2
                                , smtVarDef m ]

smtGenericScript :: VarEnv -> (VarEnv -> String -> String -> String)
                 -> BoolRep -> BoolRep -> String
smtGenericScript m f r1 r2 = smtScriptHead m r1 r2 ++ "\n" ++ f m "A" "B"

smtEQScript :: VarEnv -> BoolRep -> BoolRep -> String
smtEQScript m r1 r2 = smtGenericScript m smtEQStmt r1 r2

smtLEScript :: VarEnv -> BoolRep -> BoolRep -> String
smtLEScript m r1 r2 = smtGenericScript m smtLEStmt r1 r2

smtDisjScript :: VarEnv -> BoolRep -> BoolRep -> String
smtDisjScript m r1 r2 = smtGenericScript m smtDisjStmt r1 r2

data SMTStatus = Sat | Unsat deriving (Show, Eq)

smtCheck :: VarEnv -> BoolRep -> BoolRep -> IO [SMTStatus]
smtCheck m r1 r2 = smtMultiResponse $ smtAllScript m r1 r2

smtCheck' :: VarEnv -> BoolRep -> BoolRep -> IO [SMTStatus]
smtCheck' m r1 r2 = mapM smtResponse $ smtAllScripts m r1 r2

-- | The result states of the smt solver are translated to the
-- adequate compare outcome. The boolean value is true if the corresponding
-- set is empty.
smtStatusCompareTable :: [SMTStatus] -> (EPCompare, Bool, Bool)
smtStatusCompareTable l =
    case l of
      [Unsat, Unsat, Unsat, x] -> let b = x == Unsat in (Comparable EQ, b, b)
      [Sat, Unsat, Sat, x] -> let b = x == Unsat in (Comparable LT, b, b)
      [Sat, Sat, Unsat, x] -> let b = x == Unsat in (Comparable GT, b, b)
      [Sat, Sat, Sat, Unsat] -> (Incomparable Disjoint, False, False)
      [Sat, Sat, Sat, Sat] -> (Incomparable Overlap, False, False)
      x -> error $ "smtStatusCompareTable: malformed status " ++ show x

tripleFst :: (a, b, c) -> a
tripleFst (x, _, _) = x

smtCompare :: VarEnv -> BoolRep -> BoolRep -> IO (EPCompare, Bool, Bool)
smtCompare m r1 r2 = liftM smtStatusCompareTable $ smtCheck m r1 r2

smtCompareUnsafe :: VarEnv -> BoolRep -> BoolRep -> EPCompare
smtCompareUnsafe m r1 r2 = tripleFst $ unsafePerformIO $ smtCompare m r1 r2

smtFullCompareUnsafe :: VarEnv -> BoolRep -> BoolRep -> (EPCompare, Bool, Bool)
smtFullCompareUnsafe m r1 r2 = unsafePerformIO $ smtCompare m r1 r2

smtCompareUnsafe' :: VarEnv -> BoolRep -> BoolRep -> EPCompare
smtCompareUnsafe' m r1 r2 = tripleFst $ smtStatusCompareTable $ unsafePerformIO $ smtCheck' m r1 r2


smtResponseToStatus :: String -> SMTStatus
smtResponseToStatus s
    | s == "sat" = Sat
    | s == "unsat" = Unsat
    | s == "" = Sat
    | isInfixOf "Error" s = error $ "yices-error: " ++ s
    | otherwise = error $ "unknown yices error"

smtMultiResponse :: String -> IO [SMTStatus]
smtMultiResponse inp = do
  s <- readProcess "yices" [] inp
  return $ map smtResponseToStatus $ lines s

smtResponse :: String -> IO SMTStatus
smtResponse inp = do
  s <- readProcess "yices" [] inp
--  putStrLn "------ yices output ------"
--  putStrLn s
  return $ smtResponseToStatus $
         case lines s of
           [] -> ""
           x:_ ->  x

