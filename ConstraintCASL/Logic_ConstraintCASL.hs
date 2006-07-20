{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  portable

Here is the place where the class Logic is instantiated for CASL.
   Also the instances for Syntax an Category.
-}

{- todo:
  real implementation for map_sen
-}

module ConstraintCASL.Logic_ConstraintCASL
    ( module ConstraintCASL.Logic_ConstraintCASL
    , CASLSign
    , ConstraintCASLMor) 
    where

import Common.AS_Annotation
import Common.Result
import Common.Lexer((<<))
import Text.ParserCombinators.Parsec

import Logic.Logic

import ConstraintCASL.AS_ConstraintCASL
import ConstraintCASL.Parse_AS_Basic
import ConstraintCASL.Formula
import ConstraintCASL.StaticAna
import ConstraintCASL.ATC_ConstraintCASL()
import ConstraintCASL.Print_AS()

import CASL.AS_Basic_CASL
import CASL.ToDoc()
import CASL.SymbolParser
import CASL.MapSentence
import CASL.ATC_CASL()
import CASL.Sublogic
import CASL.Sign
import CASL.Morphism
import CASL.SymbolMapAnalysis
import CASL.Logic_CASL

data ConstraintCASL = ConstraintCASL deriving Show

instance Language ConstraintCASL where
 description _ =
  "ConstraintCASL - a restriction of CASL to constraint\ 
   \formulas over predicates"

-- dummy of "Min f e"
dummyMin :: b -> c -> Result ()
dummyMin _ _ = Result {diags = [], maybeResult = Just ()}

instance Category ConstraintCASL ConstraintCASLSign ConstraintCASLMor
    where
         -- ide :: id -> object -> morphism
         ide ConstraintCASL = idMor dummy
         -- comp :: id -> morphism -> morphism -> Maybe morphism
         comp ConstraintCASL = compose (const id)
         -- dom, cod :: id -> morphism -> object
         dom ConstraintCASL = msource
         cod ConstraintCASL = mtarget
         -- legal_obj :: id -> object -> Bool
         legal_obj ConstraintCASL = legalSign
         -- legal_mor :: id -> morphism -> Bool
         legal_mor ConstraintCASL = legalMor

-- abstract syntax, parsing (and printing)

instance Syntax ConstraintCASL ConstraintCASLBasicSpec
                SYMB_ITEMS SYMB_MAP_ITEMS
      where
         parse_basic_spec ConstraintCASL = Just $ basicSpec constraintKeywords
         parse_symb_items ConstraintCASL = Just $ symbItems []
         parse_symb_map_items ConstraintCASL = Just $ symbMapItems []

-- lattices (for sublogics) is missing

instance Sentences ConstraintCASL ConstraintCASLFORMULA () ConstraintCASLSign ConstraintCASLMor Symbol where
      map_sen ConstraintCASL m = return . mapSen (\ _ -> id) m
      parse_sentence ConstraintCASL = Just (fmap item (aFormula [] << eof))
      sym_of ConstraintCASL = symOf
      symmap_of ConstraintCASL = morphismToSymbMap
      sym_name ConstraintCASL = symName
      conservativityCheck ConstraintCASL th mor phis = 
        error "conservativityCheck ConstraintCASL nyi"
      -- fmap (fmap fst) (checkFreeType th mor phis)
      simplify_sen ConstraintCASL = 
        error "simplify_sen ConstraintCASL nyi" -- simplifySen dummyMin dummy

instance StaticAnalysis ConstraintCASL 
               ConstraintCASLBasicSpec ConstraintCASLFORMULA ()
               SYMB_ITEMS SYMB_MAP_ITEMS
               ConstraintCASLSign
               ConstraintCASLMor
               Symbol RawSymbol where
         basic_analysis ConstraintCASL = Just basicConstraintCASLAnalysis
         stat_symb_map_items ConstraintCASL = statSymbMapItems
         stat_symb_items ConstraintCASL = statSymbItems
         ensures_amalgamability ConstraintCASL (opts, diag, sink, desc) =
            error "ConstraintCASL.ensures_amalgamability not yet implemented"
             --ensuresAmalgamability opts diag sink desc

         sign_to_basic_spec ConstraintCASL _sigma _sens = Basic_spec [] -- ???

         symbol_to_raw ConstraintCASL = symbolToRaw
         id_to_raw ConstraintCASL = idToRaw
         matches ConstraintCASL = CASL.Morphism.matches
         is_transportable ConstraintCASL = isSortInjective

         empty_signature ConstraintCASL = emptySign ()
         signature_union ConstraintCASL s = return . addSig const s
         signature_difference ConstraintCASL s = return . diffSig const s
         morphism_union ConstraintCASL = morphismUnion (const id) const
         final_union ConstraintCASL = finalUnion const
         is_subsig ConstraintCASL = isSubSig trueC
         inclusion ConstraintCASL = sigInclusion dummy trueC
         cogenerated_sign ConstraintCASL = cogeneratedSign dummy
         generated_sign ConstraintCASL = generatedSign dummy
         induced_from_morphism ConstraintCASL = inducedFromMorphism dummy
         induced_from_to_morphism ConstraintCASL = 
             inducedFromToMorphism dummy trueC
         theory_to_taxonomy ConstraintCASL = 
           error "theory_to_taxonomy ConstraintCASL nyi" -- convTaxo

instance MinSL () ConstraintFORMULA
instance ProjForm () ConstraintFORMULA

instance Logic ConstraintCASL CASL_Sublogics
               ConstraintCASLBasicSpec ConstraintCASLFORMULA
               SYMB_ITEMS SYMB_MAP_ITEMS
               ConstraintCASLSign
               ConstraintCASLMor
               Symbol RawSymbol () where

         stability _ = Experimental
         proj_sublogic_epsilon ConstraintCASL = pr_epsilon dummy
         all_sublogics _ = sublogics_all [()]
