{- |
Module      :  $Header$
Description :  termination proofs for equation systems, using AProVE
Copyright   :  (c) Mingyi Liu and Till Mossakowski and Uni Bremen 2004-2005
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  xinga@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Termination proofs for equation systems, using AProVE
-}

module CASL.CCC.TerminationProof (terminationProof) where

import CASL.AS_Basic_CASL
import CASL.CCC.TermFormula
  ( unsortedTerm
  , quanti
  , arguOfTerm
  , substiF
  , sameOpsApp)

import Common.Id (Token (tokStr), Id (Id))
import Common.Utils

import System.Process
import System.Directory

import Data.List (intercalate)
import Data.Function (on)

{-
   Automatic termination proof
   using AProVE, see http://aprove.informatik.rwth-aachen.de/

   interface to AProVE system, using system
   translate CASL signature to AProVE Input Language,
   CASL formulas to AProVE term rewrite systems(TRS),
   see http://aprove.informatik.rwth-aachen.de/help/html/in/trs.html

   if a equation system is terminal, then it is computable.
-}

terminationProof :: Ord f => [FORMULA f] -> [(TERM f, FORMULA f)]
  -> IO (Maybe Bool)
terminationProof fs dms = if null fs then return $ Just True else do
  let
    allVar = nubOrd . concat
    varsStr vars str = case vars of
      [] -> str
      h : t -> varsStr t $
        (if null str then "" else str ++ " ") ++ tokStr h
    axhead =
      [ "(RULES"
      , "eq(t,t) -> true"
      , "eq(_,_) -> false"
      , "when_else(t1,true,t2) -> t1"
      , "when_else(t1,false,t2) -> t2" ]
    c_vars = "(VAR t t1 t2 " ++ varsStr (allVar $ map varOfAxiom fs) "" ++ ")"
    c_axms = axhead ++ map (`axiom2TRS` dms) fs ++ [")"]
  tmpFile <- getTempFile (unlines $ c_vars : c_axms) "Input.trs"
  aprovePath <- getEnvDef "HETS_APROVE"
                  "CASL/Termination/AProVE.jar"
  (_, proof, _) <- readProcessWithExitCode "java"
    ("-jar" : aprovePath : words "-u cli -m wst -p plain" ++ [tmpFile]) ""
  removeFile tmpFile
  return $ case words proof of
    "YES" : _ -> Just True
    "NO" : _ -> Just False
    _ -> Nothing

-- | extract all variables of a axiom
varOfAxiom :: FORMULA f -> [VAR]
varOfAxiom f = case f of
    Quantification _ vd _ _ ->
        concatMap (\ (Var_decl vs _ _) -> vs) vd
    _ -> []

-- | translate id to string
idStr :: Id -> String
idStr (Id ts _ _) = concatMap tokStr ts

-- | get the name of a operation symbol
opSymName :: OP_SYMB -> String
opSymName = idStr . opSymbName

-- | get the name of a predicate symbol
predSymName :: PRED_SYMB -> String
predSymName = idStr . predSymbName

-- | create a predicate application
predAppl :: PRED_SYMB -> [TERM f] -> String
predAppl p ts =
  predSymName p ++ termsPA ts

-- | apply function string to argument string with brackets
apply :: String -> String -> String
apply f a = f ++ "(" ++ a ++ ")"

-- | create a binary application
applyBin :: String -> String -> String -> String
applyBin o t1 t2 = apply o $ t1 ++ "," ++ t2

-- | create an eq application
applyEq :: TERM f -> TERM f -> String
applyEq = on (applyBin "eq") term2TRS

-- | translate a casl term to a term of TRS(Terme Rewrite Systems)
term2TRS :: TERM f -> String
term2TRS t = case unsortedTerm t of
  Qual_var var _ _ -> tokStr var
  Application o ts _ -> opSymName o ++ termsPA ts
  Conditional t1 f t2 _ ->
    apply "when_else" $ term2TRS t1 ++ "," ++ axiomSub f ++ "," ++ term2TRS t2
  _ -> error "CASL.CCC.TerminationProof.<term2TRS>"

-- | translate a list of casl terms to the patterns of a term in TRS
termsPA :: [TERM f] -> String
termsPA ts =
  if null ts then "" else apply "" . intercalate "," $ map term2TRS ts

{- | translate a casl axiom to TRS-rule:
a rule without condition is represented by "A -> B" in
Term Rewrite Systems; if there are some conditions, then
follow the conditions after the symbol "|".
For example : "A -> B | C -> D, E -> F, ..." -}
axiom2TRS :: Eq f => FORMULA f -> [(TERM f, FORMULA f)] -> String
axiom2TRS f doms = case quanti f of
  Relation f1 c f2 _ | c /= Equivalence -> case f2 of
    Relation f3 Equivalence f4 _ -> axiom2TRS f3 doms ++ " | "
      ++ axiom2TRS f1 doms ++ ", " ++ axiom2TRS f4 doms
    _ -> let t2 = axiom2TRS f2 doms ++ " | " in case f1 of
      Definedness t _ -> case filter (sameOpsApp t . fst) doms of
        [] -> t2 ++ apply "def" (term2TRS t) ++ " -> open"
        (te, phi) : _ -> let st = on zip arguOfTerm t te in
                    t2 ++ axiom2TRS (substiF st phi) doms
      _ -> t2 ++ axiom2TRS f1 doms
  Relation f1 Equivalence f2 _ ->
    axiom2TRS f1 doms ++ " | " ++ axiom2TRS f2 doms
  Negation f' _ -> case f' of
    Quantification {} ->
      error "CASL.CCC.TerminationProof.<axiom2TRS_Negation>"
    Definedness t _ -> term2TRS t ++ " -> undefined"
    _ -> axiomSub f' ++ " -> false"
  Definedness t _ -> apply "def" (term2TRS t) ++ " -> open"
  Equation t1 Strong t2 _ -> case t2 of
    Conditional tt1 ff tt2 _ ->
      term2TRS t1 ++ " -> " ++ term2TRS tt1 ++ " | "
      ++ axiomSub ff ++ " -> true\n"
      ++ term2TRS t1 ++ " -> " ++ term2TRS tt2 ++ " | "
      ++ axiomSub ff ++ " -> false"
    _ -> if isApp t1 then term2TRS t1 ++ " -> " ++ term2TRS t2 else
      applyEq t1 t2 ++ " -> true"
  Atom False _ -> "false -> false"
  _ -> axiomSub f ++ " -> true"

-- | check whether it is a application term
isApp :: TERM t -> Bool
isApp t = case unsortedTerm t of
  Application {} -> True
  _ -> False

-- | translate a casl axiom (without conditions) to a subrule of TRS,
axiomSub :: FORMULA f -> String
axiomSub f = case quanti f of
  Junction j fs@(_ : _) _ ->
    joinSub (if j == Con then "and" else "or") fs
  Negation f' _ -> apply "not" $ axiomSub f'
  Atom b _ -> if b then "true" else "false"
  Predication p_s ts _ -> predAppl p_s ts
  Definedness t _ -> apply "def" $ term2TRS t
  Equation t1 Strong t2 _ -> applyEq t1 t2
  Relation f1 c f2 _ -> on
    (applyBin $ if c == Equivalence then "equiv" else "implies")
    axiomSub f1 f2
  _ -> error "CASL.CCC.TerminationProof.axiomSub.<axiomSub>"

-- | translate a list of junctive casl formulas to a subrule of TRS
joinSub :: String -> [FORMULA f] -> String
joinSub op = foldr1 (applyBin op) . map axiomSub
