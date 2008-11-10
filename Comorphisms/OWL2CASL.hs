{- |
Module      :  $Header$
Description :  Comorphism from OWL 1.1 to CASL_Dl
Copyright   :  (c) Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (via Logic.Logic)

a not yet implemented comorphism
-}

module Comorphisms.OWL2CASL
    (OWL2CASL(..)
    )
    where

import Logic.Logic
import Logic.Comorphism
import Common.AS_Annotation
import Common.Result
import Common.Id
import Control.Monad
import Data.Char
import qualified Data.Set as Set
import qualified Data.Map as Map

--OWL = domain
import OWL.Logic_OWL
import OWL.AS
import qualified OWL.Sign as OS

--CASL_DL = codomain
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism
import CASL.Sublogic

import Common.ProofTree

data OWL2CASL = OWL2CASL deriving Show

instance Language OWL2CASL

instance Comorphism
    OWL2CASL        -- comorphism
    OWL             -- lid domain
    ()              -- sublogics domain
    OntologyFile    -- Basic spec domain
    OS.Sentence     -- sentence domain
    ()              -- symbol items domain
    ()              -- symbol map items domain
    OS.Sign         -- signature domain
    OWL_Morphism    -- morphism domain
    ()              -- symbol domain
    ()              -- rawsymbol domain
    ProofTree       -- proof tree codomain
    CASL            -- lid codomain
    CASL_Sublogics  -- sublogics codomain
    CASLBasicSpec   -- Basic spec codomain
    CASLFORMULA     -- sentence codomain
    SYMB_ITEMS      -- symbol items codomain
    SYMB_MAP_ITEMS  -- symbol map items codomain
    CASLSign        -- signature codomain
    CASLMor         -- morphism codomain
    Symbol          -- symbol codomain
    RawSymbol       -- rawsymbol codomain
    ProofTree       -- proof tree domain
    where
      sourceLogic OWL2CASL    = OWL
      sourceSublogic OWL2CASL = ()
      targetLogic OWL2CASL    = CASL
      mapSublogic OWL2CASL _  = Just $ cFol
        { cons_features = emptyMapConsFeature }
      map_theory OWL2CASL     = mapTheory
      map_morphism OWL2CASL   = fail "map_morphism OWL2CASL"

-- Primary concepts stay in OWL, but non-primary concepts cannot be
-- superconcepts of primary ones

-- | OWL topsort Thing
thing :: SORT
thing = stringToId "Thing"

-- | OWL bottom
noThing :: PRED_SYMB
noThing =
     (Qual_pred_name (stringToId "Nothing")
                         (Pred_type [thing] nullRange) nullRange)

-- | OWL Data topSort DATA
dataS :: SORT
dataS = stringToId "DATA"

predefSorts :: Set.Set SORT
predefSorts = Set.fromList [dataS, thing]

hetsPrefix :: String
hetsPrefix = "gn_"

mapSign :: OS.Sign                 -- ^ OWL signature
        -> Result CASLSign         -- ^ CASL signature
mapSign sig =
    do
      let conc = Set.union (OS.concepts sig) (OS.primaryConcepts sig)
      ooConcs <- foldM (\x y ->
                               do
                                 nId <- uriToId y
                                 return $ (Map.insert nId
                                    (Set.singleton (PredType [thing])) x)
                            )
                   Map.empty $ Set.toList conc
      let oConcs = Map.union ooConcs $ foldl (Map.union) Map.empty $
               [
                Map.singleton (stringToId "Thing")
                       (Set.singleton (PredType [thing]))
               ,Map.singleton (stringToId "Nothing")
                       (Set.singleton (PredType [thing]))
               ]
      let objProps = OS.indValuedRoles sig
      oObjProps <- foldM (\x y ->
                               do
                                 nId <- uriToId y
                                 return $ (Map.insert nId
                                    (Set.singleton (PredType [thing,thing])) x)
                            )
                   Map.empty $ Set.toList objProps
      let inDis = OS.individuals sig
      oInDis <- foldM (\x y ->
                               do
                                 nId <- uriToId y
                                 return $ (Map.insert nId
                                    (Set.singleton (OpType Total [] thing)) x)
                            )
                   Map.empty $ Set.toList inDis
      return $ (emptySign ())
             {
               sortSet = predefSorts
             , emptySortSet = Set.empty
             , predMap = oConcs `Map.union` oObjProps
             , opMap = oInDis
             }

predefinedSentences :: [SenAttr (FORMULA ()) [Char]]
predefinedSentences =
    [
     makeNamed "nothing in Nothing" $
     Quantification Universal
     [Var_decl [mk_Name 1] thing nullRange]
     (
      Negation
      (
       Predication
       noThing
       [Qual_var (mk_Name 1) thing nullRange]
       nullRange
      )
      nullRange
     )
     nullRange
    ,
     makeNamed "thing in Thing" $
     Quantification Universal
     [Var_decl [mk_Name 1] thing nullRange]
     (
       Predication
       (Qual_pred_name (stringToId "Thing")
                           (Pred_type [thing] nullRange) nullRange)
       [Qual_var (mk_Name 1) thing nullRange]
       nullRange
     )
     nullRange
    ,
     makeNamed "thing is not data" $
     Quantification Universal
     [Var_decl [mk_Name 1] thing nullRange]
     (
      Negation
      (
       Membership
       (Qual_var (mk_Name 1) thing nullRange)
       dataS
       nullRange
      )
      nullRange
     )
     nullRange
    ,
     makeNamed "data is not thing" $
     Quantification Universal
     [Var_decl [mk_Name 1] thing nullRange]
     (
      Negation
      (
       Membership
       (Qual_var (mk_Name 1) dataS nullRange)
       thing
       nullRange
      )
      nullRange
     )
     nullRange
    ]

mapTheory :: (OS.Sign, [Named OS.Sentence])
             -> Result (CASLSign, [Named CASLFORMULA])
mapTheory (owlSig, owlSens) =
    do
      cSig  <- mapSign owlSig
      cSens <- mapM (mapSentence cSig) owlSens
      return $ (cSig, predefinedSentences ++ cSens)

-- | mapping of OWL to CASL_DL formulae
mapSentence :: CASLSign                      -- ^ CASL Signature
            -> Named OS.Sentence             -- ^ OWL Sentence
            -> Result (Named CASLFORMULA)    -- ^ CASL_DL Sentence
mapSentence cSig inSen =
    let
        sName = senAttr    inSen
        sDef  = isDef      inSen
        sAx   = isAxiom    inSen
        wTh   = wasTheorem inSen
        sen   = sentence   inSen
        sAnno = simpAnno   inSen
    in
      case sen of
        OS.OWLAxiom ax   ->
            do
              outAx <- mapAxiom cSig ax
              return $ SenAttr
                         {
                           senAttr    = sName
                         , isAxiom    = sAx
                         , isDef      = sDef
                         , wasTheorem = wTh
                         , sentence   = outAx
                         , simpAnno   = sAnno
                         }
        OS.OWLFact  fact ->
            do
              outFact <- mapAxiom cSig fact
              return $ SenAttr
                         {
                           senAttr    = sName
                         , isAxiom    = sAx
                         , isDef      = sDef
                         , wasTheorem = wTh
                         , sentence   = outFact
                         , simpAnno   = sAnno
                         }

-- | Mapping of Axioms
mapAxiom :: CASLSign               -- ^ CASL Signature
         -> Axiom                  -- ^ OWL Axiom
         -> Result CASLFORMULA     -- ^ CASL_DL Formula
mapAxiom cSig ax =
    let
        a = 1
        b = 2
        c = 3
    in
      case ax of
        PlainAxiom _ pAx ->
            case pAx of
              SubClassOf sub super ->
                  do
                    domT <- mapDescription cSig sub   a
                    codT <- mapDescription cSig super a
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                                       thing nullRange]
                               (Implication
                                domT
                                codT
                                True
                                nullRange) nullRange
              EquivOrDisjointClasses eD dS ->
                  do
                    decrsS <- mapDescriptionListP cSig a $ comPairs dS dS
                    let decrsP = map (\(x,y) -> Conjunction [x,y] nullRange) decrsS
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                                       thing nullRange]
                               (
                                case eD of
                                  Equivalent -> Conjunction decrsP nullRange
                                  Disjoint   ->
                                      Negation
                                      (
                                       Conjunction decrsP nullRange
                                      ) nullRange
                               ) nullRange
              DisjointUnion cls sD ->
                  do
                    decrs  <- mapDescriptionList cSig a sD
                    decrsS <- mapDescriptionListP cSig a $ comPairs sD sD
                    let decrsP = map (\(x,y) -> Conjunction [x,y] nullRange) decrsS
                    mcls <- mapClassURI cSig cls (mk_Name a)
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                             thing nullRange]
                               (
                                Equivalence
                                (                      -- The class
                                  mcls
                                )
                                (                      -- The rest
                                  Conjunction
                                  [
                                   Disjunction decrs nullRange
                                  ,Negation
                                   (
                                    Conjunction decrsP nullRange
                                   )
                                   nullRange
                                  ]
                                  nullRange
                                )
                                nullRange
                               ) nullRange
              SubObjectPropertyOf ch op -> mapSubObjProp cSig ch op c
              EquivOrDisjointObjectProperties disOrEq oExLst ->
                  do
                    pairs <- mapComObjectPropsList cSig oExLst a b
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                                       thing nullRange,
                                                       Var_decl [mk_Name b]
                                                       thing nullRange]
                               (
                                Conjunction
                                (
                                 case disOrEq of
                                   Equivalent ->
                                       map (\(x,y) ->
                                                Equivalence x y nullRange) pairs
                                   Disjoint   ->
                                       map (\(x,y) ->
                                                (Negation
                                                 (Conjunction [x,y] nullRange)
                                                 nullRange
                                                )
                                           ) pairs
                                )
                                nullRange
                               )
                               nullRange
              ObjectPropertyDomainOrRange domOrRn objP descr ->
                        do
                          tobjP <- mapObjProp cSig objP a b
                          tdsc  <- mapDescription cSig descr $
                                   case domOrRn of
                                     ObjDomain -> a
                                     ObjRange  -> b
                          let vars = case domOrRn of
                                       ObjDomain -> (mk_Name a, mk_Name b)
                                       ObjRange  -> (mk_Name b, mk_Name a)
                          return $ Quantification Universal
                                     [Var_decl [fst vars] thing nullRange]
                                     (
                                      Quantification Existential
                                         [Var_decl [snd vars] thing nullRange]
                                         (
                                          Implication
                                          (
                                           tobjP
                                          )
                                          (
                                           tdsc
                                          )
                                          True
                                          nullRange
                                         )
                                      nullRange
                                     )
                                     nullRange
              InverseObjectProperties o1 o2 ->
                  do
                    so1 <- mapObjProp cSig o1 a b
                    so2 <- mapObjProp cSig o2 b a
                    return $ Quantification Universal
                             [Var_decl [mk_Name a] thing nullRange
                             ,Var_decl [mk_Name b] thing nullRange]
                             (
                              Equivalence
                              so1
                              so2
                              nullRange
                             )
                             nullRange
              ObjectPropertyCharacter cha o ->
                  case cha of
                    Functional ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o a c
                          return $ Quantification Universal
                                     [Var_decl [mk_Name a] thing nullRange
                                     ,Var_decl [mk_Name b] thing nullRange
                                     ,Var_decl [mk_Name c] thing nullRange
                                     ]
                                     (
                                      Implication
                                      (
                                       Conjunction [so1, so2] nullRange
                                      )
                                      (
                                       Strong_equation
                                       (
                                        Qual_var (mk_Name b) thing nullRange
                                       )
                                       (
                                        Qual_var (mk_Name c) thing nullRange
                                       )
                                       nullRange
                                      )
                                      True
                                      nullRange
                                     )
                                     nullRange
                    InverseFunctional ->
                        do
                          so1 <- mapObjProp cSig o a c
                          so2 <- mapObjProp cSig o b c
                          return $ Quantification Universal
                                     [Var_decl [mk_Name a] thing nullRange
                                     ,Var_decl [mk_Name b] thing nullRange
                                     ,Var_decl [mk_Name c] thing nullRange
                                     ]
                                     (
                                      Implication
                                      (
                                       Conjunction [so1, so2] nullRange
                                      )
                                      (
                                       Strong_equation
                                       (
                                        Qual_var (mk_Name a) thing nullRange
                                       )
                                       (
                                        Qual_var (mk_Name b) thing nullRange
                                       )
                                       nullRange
                                      )
                                      True
                                      nullRange
                                     )
                                     nullRange
                    Reflexive  ->
                        do
                          so <- mapObjProp cSig o a a
                          return $
                                 Quantification Universal
                                   [Var_decl [mk_Name a] thing nullRange]
                                   (
                                    Implication
                                     (
                                      Membership
                                      (Qual_var (mk_Name a) thing nullRange)
                                      thing
                                      nullRange
                                     )
                                     so
                                     True
                                     nullRange
                                   )
                                   nullRange
                    Irreflexive ->
                        do
                          so <- mapObjProp cSig o a a
                          return $
                                 Quantification Universal
                                   [Var_decl [mk_Name a] thing nullRange]
                                   (
                                    Implication
                                    (
                                     Membership
                                     (Qual_var (mk_Name a) thing nullRange)
                                     thing
                                     nullRange
                                    )
                                    (
                                     Negation
                                     so
                                    nullRange
                                    )
                                    True
                                    nullRange
                                   )
                                   nullRange
                    Symmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return $
                           Quantification Universal
                               [Var_decl [mk_Name a] thing nullRange
                               ,Var_decl [mk_Name b] thing nullRange]
                               (
                                Implication
                                so1
                                so2
                                True
                                nullRange
                               )
                               nullRange
                    Asymmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return $
                           Quantification Universal
                               [Var_decl [mk_Name a] thing nullRange
                               ,Var_decl [mk_Name b] thing nullRange]
                               (
                                Implication
                                so1
                                (Negation so2 nullRange)
                                True
                                nullRange
                               )
                               nullRange
                    Antisymmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return $
                           Quantification Universal
                               [Var_decl [mk_Name a] thing nullRange
                               ,Var_decl [mk_Name b] thing nullRange]
                               (
                                Implication
                                 (Conjunction [so1, so2] nullRange)
                                 (
                                  Strong_equation
                                  (
                                   Qual_var (mk_Name a) thing nullRange
                                  )
                                  (
                                   Qual_var (mk_Name b) thing nullRange
                                  )
                                  nullRange
                                 )
                                True
                                nullRange
                               )
                               nullRange
                    Transitive ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b c
                          so3 <- mapObjProp cSig o a c
                          return $
                           Quantification Universal
                               [Var_decl [mk_Name a] thing nullRange
                               ,Var_decl [mk_Name b] thing nullRange
                               ,Var_decl [mk_Name c] thing nullRange]
                               (
                                Implication
                                (
                                 Conjunction [so1, so2] nullRange
                                )
                                (
                                 so3
                                )
                                True
                                nullRange
                               )
                               nullRange
              SubDataPropertyOf dP1 dP2 ->
                  do
                    l <- mapDataProp cSig dP1 a b
                    r <- mapDataProp cSig dP2  a b
                    return $ Quantification Universal
                               [Var_decl [mk_Name a] thing nullRange, Var_decl [mk_Name b] dataS nullRange]
                               (
                                Implication
                                l
                                r
                                True
                                nullRange
                               )
                               nullRange
              EquivOrDisjointDataProperties disOrEq dlst ->
                  do
                    pairs <- mapComDataPropsList cSig dlst a b
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                                       thing nullRange,
                                                       Var_decl [mk_Name b]
                                                       dataS nullRange]
                               (
                                Conjunction
                                (
                                 case disOrEq of
                                   Equivalent ->
                                       map (\(x,y) ->
                                                Equivalence x y nullRange) pairs
                                   Disjoint   ->
                                       map (\(x,y) ->
                                                (Negation
                                                 (Conjunction [x,y] nullRange)
                                                 nullRange
                                                )
                                           ) pairs
                                )
                                nullRange
                               )
                               nullRange
              DataPropertyDomainOrRange _ _ ->
                  fail "DataPropertyDomainOrRange nyi"
              FunctionalDataProperty _ ->
                  fail "FunctionalDataProperty nyi"
              SameOrDifferentIndividual sameOrDiff indis ->
                  do
                    inD <- mapM (mapIndivURI cSig) indis
                    let inDL = comPairs inD inD
                    return $ Conjunction
                             (map (\(x,y) ->
                                      case sameOrDiff of
                                        Same      -> Strong_equation x y nullRange
                                        Different -> Negation (Strong_equation x y nullRange) nullRange
                                 ) inDL)
                             nullRange
              ClassAssertion indi cls ->
                  do
                    inD  <- mapIndivURI cSig indi
                    ocls <- mapDescription cSig cls a
                    return $ Quantification Universal [Var_decl [mk_Name a]
                                                       thing nullRange]
                             (
                              Implication
                              (Strong_equation
                               (Qual_var (mk_Name a) thing nullRange)
                               inD
                               nullRange
                              )
                              (
                               ocls
                              )
                              True
                              nullRange
                             )
                             nullRange
              ObjectPropertyAssertion ass ->
                  case ass of
                    Assertion objProp posNeg sourceInd targetInd ->
                              do
                                inS <- mapIndivURI cSig sourceInd
                                inT <- mapIndivURI cSig targetInd
                                oPropH <- mapObjProp cSig objProp a b
                                let oProp = case posNeg of
                                              Positive -> oPropH
                                              Negative -> Negation
                                                           oPropH
                                                           nullRange
                                return $ Quantification Universal
                                           [Var_decl [mk_Name a]
                                                     thing nullRange
                                           ,Var_decl [mk_Name b]
                                                     thing nullRange]
                                         (
                                          Implication
                                          (
                                           Conjunction
                                           [
                                            Strong_equation
                                            (Qual_var (mk_Name a) thing nullRange)
                                            inS
                                            nullRange
                                           ,Strong_equation
                                            (Qual_var (mk_Name b) thing nullRange)
                                            inT
                                            nullRange
                                           ]
                                           nullRange
                                          )
                                          (
                                           oProp
                                          )
                                          True
                                          nullRange
                                         )
                                         nullRange
              DataPropertyAssertion _ ->
                  fail "DataPropertyAssertion nyi"
              Declaration _ ->
                  return $ True_atom nullRange
        EntityAnno _  ->
              return $ True_atom nullRange

-- | Mapping along ObjectPropsList for creation of pairs for commutative operations
mapComObjectPropsList :: CASLSign                    -- ^ CASLSignature
                      -> [ObjectPropertyExpression]
                      -> Int                         -- ^ First variable
                      -> Int                         -- ^ Last  variable
                      -> Result [(CASLFORMULA,CASLFORMULA)]
mapComObjectPropsList cSig props num1 num2 =
    do
      oProps   <- mapM (\(x,z) ->
                            do
                              l <- mapObjProp cSig x num1 num2
                              r <- mapObjProp cSig z num1 num2
                              return (l,r)
                       ) $
                  comPairs props props
      return $ oProps

-- | Mapping of subobj properties
mapSubObjProp :: CASLSign
              -> SubObjectPropertyExpression
              -> ObjectPropertyExpression
              -> Int
              -> Result CASLFORMULA
mapSubObjProp cSig prop oP num1 =
    let
        num2 = num1 + 1
    in
      case prop of
        OPExpression oPL ->
            do
              l <- mapObjProp cSig oPL num1 num2
              r <- mapObjProp cSig oP num1 num2
              return $ Quantification Universal
                     [Var_decl [mk_Name num1] thing nullRange, Var_decl [mk_Name num2] thing nullRange]
                     (
                      Implication
                      l
                      r
                      True
                      nullRange
                     )
                     nullRange
        SubObjectPropertyChain props ->
            do
              let zprops   = zip (tail props) [num2 ..]
                  (_,vars) = unzip $ zprops
              oProps   <- mapM (\(z,x,y) -> mapObjProp cSig z x y) $
                                zip3 props ((num1:vars) ++ [num2]) $
                                     tail ((num1:vars) ++ [num2])
              ooP      <- mapObjProp cSig oP num1 num2
              return $ Quantification Universal
                     [Var_decl [mk_Name num1] thing nullRange, Var_decl [mk_Name num2] thing nullRange]
                     (
                      Quantification Existential
                         (
                          map (\x -> Var_decl [mk_Name x] thing nullRange) vars
                         )
                         (
                          Implication
                          (Conjunction oProps nullRange)
                          ooP
                          True
                          nullRange
                         )
                       nullRange
                     )
                    nullRange

-- | Mapping along DataPropsList for creation of pairs for commutative operations
mapComDataPropsList :: CASLSign
                      -> [DataPropertyExpression]
                      -> Int                         -- ^ First variable
                      -> Int                         -- ^ Last  variable
                      -> Result [(CASLFORMULA,CASLFORMULA)]
mapComDataPropsList cSig props num1 num2 =
    do
      oProps   <- mapM (\(x,z) ->
                            do
                              l <- mapDataProp cSig x num1 num2
                              r <- mapDataProp cSig z num1 num2
                              return (l,r)
                       ) $
                  comPairs props props
      return $ oProps

-- | Mapping of data properties
mapDataProp :: CASLSign
            -> DataPropertyExpression
            -> Int
            -> Int
            -> Result CASLFORMULA
mapDataProp _ dP nO nD =
    do
      let
          l = mk_Name nO
          r = mk_Name nD
      ur <- uriToId dP
      return $ Predication
                 (Qual_pred_name ur (Pred_type [thing,dataS] nullRange) nullRange)
                 [Qual_var l thing nullRange, Qual_var r dataS nullRange]
                 nullRange

-- | Mapping of obj props
mapObjProp :: CASLSign
              -> ObjectPropertyExpression
              -> Int
              -> Int
              -> Result CASLFORMULA
mapObjProp cSig ob num1 num2 =
    case ob of
      OpURI u ->
          do
            let l = mk_Name num1
                r = mk_Name num2
            ur <- uriToId u
            return $ Predication
                       (Qual_pred_name ur (Pred_type [thing,thing] nullRange) nullRange)
                       [Qual_var l thing nullRange, Qual_var r thing nullRange]
                       nullRange
      InverseOp u ->
          mapObjProp cSig u num2 num1

-- | Mapping of obj props with Individuals
mapObjPropI :: CASLSign
              -> ObjectPropertyExpression
              -> Int
              -> IndividualURI
              -> Result CASLFORMULA
mapObjPropI cSig ob num1 indivID =
    case ob of
      OpURI u ->
          do
            let l = mk_Name num1
            iT <- mapIndivURI cSig indivID
            ur <- uriToId u
            return $ Predication
                       (Qual_pred_name ur
                        (Pred_type [thing,thing] nullRange) nullRange)
                       [Qual_var l thing nullRange,
                        iT
                       ]
                       nullRange
      InverseOp _ -> fail "cannot map this"

-- | Mapping of Class URIs
mapClassURI :: CASLSign
            -> OwlClassURI
            -> Token
            -> Result CASLFORMULA
mapClassURI _ uril uid =
    do
      ur <- uriToId uril
      return $ Predication
                  (Qual_pred_name (ur) (Pred_type [thing] nullRange) nullRange)
                  [Qual_var uid thing nullRange]
                  nullRange

-- | Mapping of Individual URIs
mapIndivURI :: CASLSign
            -> IndividualURI
            -> Result (TERM ())
mapIndivURI _ uriI =
    do
      ur <- uriToId uriI
      return $ Application
                 (
                  Qual_op_name
                  ur
                  (Op_type Total [] thing nullRange)
                  nullRange
                 )
                 []
                 nullRange

-- | Extracts Id from URI
uriToId :: URI
        -> Result Id
uriToId ur =
    let
        repl a = if (isAlphaNum a)
                  then
                      a
                  else
                      '_'
        nP = map repl $ namePrefix   ur
        lP = map repl $ localPart    ur
        nU = map repl $ namespaceUri ur
    in
      do
        return $ stringToId $ nU ++ "" ++ nP ++ "" ++ lP

-- | Mapping of a list of descriptions
mapDescriptionList :: CASLSign
                      -> Int
                      -> [Description]
                      -> Result [CASLFORMULA]
mapDescriptionList cSig n lst =
    do
      olst <- mapM (\(x,y) -> mapDescription cSig x y)
                                $ zip lst $ replicate (length lst) n
      return olst

-- | Mapping of a list of pairs of descriptions
mapDescriptionListP :: CASLSign
                    -> Int
                    -> [(Description, Description)]
                    -> Result [(CASLFORMULA, CASLFORMULA)]
mapDescriptionListP cSig n lst =
    do
      let (l, r) = unzip lst
      llst  <- mapDescriptionList cSig n l
      rlst  <- mapDescriptionList cSig n r
      let olst = zip llst rlst
      return olst

-- | Build a name
mk_Name :: Int -> Token
mk_Name i = mkSimpleId $ hetsPrefix ++ show i

-- | Get all distinct pairs for commutative operations
comPairs :: [t] -> [t1] -> [(t, t1)]
comPairs [] []     = []
comPairs _  []     = []
comPairs [] _      = []
comPairs (a:as) (_:bs) = zip (replicate (length bs) a) bs ++ comPairs as bs

-- | mapping of OWL Descriptions
mapDescription :: CASLSign
               -> Description              -- ^ OWL Description
               -> Int                      -- ^ Current Variablename
               -> Result CASLFORMULA       -- ^ CASL_DL Formula
mapDescription cSig des var =
    case des of
      OWLClass cl            -> mapClassURI cSig cl (mk_Name var)
      ObjectJunction jt desL ->
          do
            desO <- mapM (\x -> mapDescription cSig x var) desL
            case jt of
              UnionOf        ->
                  do
                    return $ Disjunction desO nullRange
              IntersectionOf ->
                  do
                    return $ Conjunction desO nullRange
      ObjectComplementOf descr ->
             do
               desO <- mapDescription cSig descr var
               return $ Negation desO nullRange
      ObjectOneOf indS ->
          do
            indO <- mapM (mapIndivURI cSig) indS
            let varO  = Qual_var (mk_Name var) thing nullRange
            let forms = map (\y ->
                                 Strong_equation varO y nullRange)
                                 indO
            return $ Disjunction forms nullRange
      ObjectValuesFrom qt oprop descr ->
        do
          opropO <- mapObjProp cSig oprop var (var + 1)
          descO  <- mapDescription cSig descr (var + 1)
          case qt of
            AllValuesFrom  ->
                return $ Quantification Existential [Var_decl [mk_Name
                                                               (var + 1)]
                                                       thing nullRange]
                       (
                        Conjunction
                        [opropO, descO]
                        nullRange
                       )
                       nullRange
            SomeValuesFrom ->
                return $ Quantification Universal [Var_decl [mk_Name
                                                               (var + 1)]
                                                       thing nullRange]
                       (
                        Implication
                        opropO descO
                        True
                        nullRange
                       )
                       nullRange
      ObjectExistsSelf oprop ->
             do
               opropO <- mapObjProp cSig oprop var var
               return opropO
      ObjectHasValue oprop indiv ->
          do
            opropO <- mapObjPropI cSig oprop var indiv
            return $ opropO
      ObjectCardinality c ->
          case c of
            Cardinality ct n oprop Nothing
                 ->
                   do
                     let vlst = [(var+1) .. (n+var+1)]
                         vlstM = [(var+1) .. (n+var+2)]
                         dlst = map (\(x,y) ->
                                     Negation
                                     (
                                        Strong_equation
                                         (Qual_var (mk_Name x) thing nullRange)
                                         (Qual_var (mk_Name y) thing nullRange)
                                         nullRange
                                     )
                                     nullRange
                                    ) $ comPairs vlst vlst
                         dlstM = map (\(x,y) ->
                                     Negation
                                     (
                                        Strong_equation
                                         (Qual_var (mk_Name x) thing nullRange)
                                         (Qual_var (mk_Name y) thing nullRange)
                                         nullRange
                                     )
                                     nullRange
                                    ) $ comPairs vlstM vlstM

                         qVars = map (\x ->
                                          Var_decl [mk_Name x]
                                                    thing nullRange
                                     ) vlst
                         qVarsM = map (\x ->
                                          Var_decl [mk_Name x]
                                                    thing nullRange
                                     ) vlstM
                     oProps <- mapM (\x -> mapObjProp cSig oprop var x) vlst
                     oPropsH <- mapM (\x -> mapObjProp cSig oprop var x) vlst
                     let oPropsM = map (\x ->
                                          Negation
                                          x nullRange) oPropsH
                     let minLst = Quantification Existential
                                  qVars
                                  (
                                   Conjunction
                                   (dlst ++ oProps)
                                   nullRange
                                  )
                                  nullRange
                     let maxLst = Quantification Universal
                                  qVarsM
                                  (
                                   Implication
                                   (Conjunction dlstM nullRange)
                                   (Disjunction oPropsM nullRange)
                                   True
                                   nullRange
                                  )
                                  nullRange
                     case ct of
                       MinCardinality -> return minLst
                       MaxCardinality -> return maxLst
                       ExactCardinality -> return $
                                           Conjunction
                                           [minLst, maxLst]
                                           nullRange
            Cardinality _ _ _ (Just _)
                 ->
                   do
                     fail "qualified cardinality restriction nyi"
      DataValuesFrom _ _ _ _ -> fail "data handling nyi"
      DataHasValue _ _       -> fail "data handling nyi"
      DataCardinality _      -> fail "data handling nyi"
