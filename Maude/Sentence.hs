{- |
Module      :  $Header$
Description :  Sentences for Maude
Copyright   :  (c) Martin Kuehl, Uni Bremen 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  mkhl@informatik.uni-bremen.de
Stability   :  experimental
Portability :  portable

Definition of sentences for Maude.
-}
{-
  Ref.

  ...
-}

module Maude.Sentence where

import Maude.AS_Maude
import Maude.Printing
import Maude.Meta

import Common.Doc
import Common.DocUtils

data Sentence = Membership Membership
              | Equation Equation
              | Rule Rule
    deriving (Show, Read, Ord, Eq)


instance Pretty Sentence where
  pretty (Membership mb) = text $ printMb mb
  pretty (Equation eq) = text $ printEq eq
  pretty (Rule rl) = text $ printRl rl

instance HasSorts Sentence where
    getSorts sen = case sen of
        Membership mb -> getSorts mb
        Equation eq   -> getSorts eq
        Rule rl       -> getSorts rl
    mapSorts mp sen = case sen of
        Membership mb -> Membership $ mapSorts mp mb
        Equation eq   -> Equation $ mapSorts mp eq
        Rule rl       -> Rule $ mapSorts mp rl

instance HasOps Sentence where
    getOps sen = case sen of
        Membership mb -> getOps mb
        Equation eq   -> getOps eq
        Rule rl       -> getOps rl
    mapOps mp sen = case sen of
        Membership mb -> Membership $ mapOps mp mb
        Equation eq   -> Equation $ mapOps mp eq
        Rule rl       -> Rule $ mapOps mp rl

instance HasLabels Sentence where
    getLabels sen = case sen of
        Membership mb -> getLabels mb
        Equation eq   -> getLabels eq
        Rule rl       -> getLabels rl
    mapLabels mp sen = case sen of
        Membership mb -> Membership $ mapLabels mp mb
        Equation eq   -> Equation $ mapLabels mp eq
        Rule rl       -> Rule $ mapLabels mp rl


-- | extract the Sentences of a Module
getSentences :: Spec -> [Sentence]
getSentences (Spec _ _ stmts) = let
            insert stmt = case stmt of
                MbStmnt mb -> (:) (Membership mb)
                EqStmnt eq -> (:) (Equation eq)
                RlStmnt rl -> (:) (Rule rl)
                _          -> id
        in foldr insert [] stmts
