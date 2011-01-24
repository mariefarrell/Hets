{- |
Module      :  $Header$
Description :  Static Analysis for EnCL
Copyright   :  (c) Dominik Dietrich, Ewaryst Schulz, DFKI Bremen 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Ewaryst.Schulz@dfki.de
Stability   :  experimental
Portability :  portable

Static Analysis for EnCL including elimination procedure for extended parameters
-}


module CSL.Analysis
{-    ( splitSpec
    , basicCSLAnalysis
    , splitAS
    , Guard(..)
    , Guarded(..)
    , dependencySortAS
    , getDependencyRelation
    , epElimination
    , topsortDirect
    , topsort
-- basicCSLAnalysis
-- ,mkStatSymbItems
-- ,mkStatSymbMapItem
-- ,inducedFromMorphism
-- ,inducedFromToMorphism
-- , signatureColimit
    ) -}
    where

import Common.ExtSign
import Common.AS_Annotation
import Common.Id
import Common.Result
import Common.Utils (mapAccumLM)
import Common.Doc
import Common.DocUtils

import CSL.AS_BASIC_CSL
import CSL.Symbol
import CSL.Fold
import CSL.Sign as Sign
import CSL.EPRelation

import Control.Monad
import qualified Data.Tree as Tr
import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.List
import Data.Maybe

-- * Diagnosis Types and Functions

-- | generates a named formula
withName :: Annoted CMD -> Int -> Named CMD
withName f i = (makeNamed (if label == "" then "Ax_" ++ show i
                                   else label) $ item f)
               { isAxiom = not isTheorem }
    where
      label = getRLabel f
      annos = r_annos f
      isImplies' = foldl (\ y x -> isImplies x || y) False annos
      isImplied' = foldl (\ y x -> isImplied x || y) False annos
      isTheorem = isImplies' || isImplied'


-- | takes a signature and a formula and a number. 
-- It analyzes the formula and returns a formula with diagnosis
analyzeFormula :: Sign.Sign -> (Annoted CMD) -> Int -> Result (Named CMD)
analyzeFormula _ f i =
    return $ withName f{ item = staticUpdate $ item f } i


-- | Extracts the axioms and the signature of a basic spec
splitSpec :: BASIC_SPEC -> Sign.Sign -> Result (Sign.Sign, [Named CMD])
splitSpec (Basic_spec specitems) sig =
    do
      ((newsig, _), mNCmds) <- mapAccumLM anaBasicItem (sig, 0) specitems
      return (newsig, catMaybes mNCmds)

anaBasicItem :: (Sign.Sign, Int) -> Annoted BASIC_ITEM
             -> Result ((Sign.Sign, Int), Maybe (Named CMD))
anaBasicItem (sign, i) itm =
    case item itm of
      Op_decl (Op_item tokens _) -> return ((addTokens sign tokens, i), Nothing)
      Var_decls l -> return ((addVarDecls sign l, i), Nothing)
      Axiom_item annocmd ->
          do
            ncmd <- analyzeFormula sign annocmd i
            return ((sign, i+1), Just ncmd)

-- | adds the specified tokens to the signature
addTokens :: Sign.Sign -> [Token] -> Sign.Sign
addTokens sign tokens = let f res itm = addToSig res (simpleIdToId itm)
                                        $ optypeFromArity 0
                        in foldl f sign tokens



-- | adds the specified var items to the signature
addVarDecls :: Sign.Sign -> [VAR_ITEM] -> Sign.Sign
addVarDecls sign vitems = foldl f sign vitems where
    f res (Var_item toks dom _) = addVarItem res toks dom

{- | stepwise extends an initially empty signature by the basic spec bs.
 The resulting spec contains analyzed axioms in it. The result contains:
 (1) the basic spec
 (2) the new signature + the added symbols
 (3) sentences of the spec
-}
basicCSLAnalysis :: (BASIC_SPEC, Sign, a)
                 -> Result (BASIC_SPEC, ExtSign Sign Symbol, [Named CMD])
basicCSLAnalysis (bs, sig, _) =
    do 
      (newSig, ncmds) <- splitSpec bs sig
      let newSyms = Set.map Symbol $ Map.keysSet
                    $ Map.difference (items newSig) $ items sig
      return (bs, ExtSign newSig newSyms, ncmds)

-- | A function which regroups all updates on a CMD during the static analysis.
staticUpdate :: CMD -> CMD
staticUpdate = handleFunAssignment . handleBinder

-- | Replaces the function-arguments in functional assignments by variables.
handleFunAssignment :: CMD -> CMD
handleFunAssignment (Ass (Op f epl al@(_:_) rg) e) =
   let (env, al') = varSet al in Ass (Op f epl al' rg) $ constsToVars env e

handleFunAssignment x = x

{- | If element x is at position i in the first list and there is an entry (i,y)
   in the second list then the resultlist has element y at position i. All 
   positions not mentioned by the second list have identical values in the first
   and the result list. 
-}
replacePositions :: [a] -> [(Int, a)] -> [a]
replacePositions l posl =
    let f (x, _) (y, _) = compare x y
        -- the actual merge function
        g _ l' [] = l'
        g _ [] _ = error "replacePositions: positions left for replacement"
        g i (a:l1) l2'@((j,b):l2) =
            if i == j then b:g (i+1) l1 l2 else a:g (i+1) l1 l2'
    -- works only if the positions are in ascending order
    in g 0 l $ sortBy f posl

-- | Replaces the binding-arguments in binders by variables.
handleBinder :: CMD -> CMD
handleBinder cmd =
    let substBinderArgs bvl bbl args =
            -- compute the var set from the given positions
            let (vs, vl) = varSet $ map (args!!) bvl
                -- compute the substituted bodyexpressionlist
                bl = map (constsToVars vs . (args!!)) bbl
            in replacePositions args $ zip (bvl ++ bbl) $ vl ++ bl
        substRec =
            passRecord
            { foldAss = \ cmd' _ def ->
                case cmd' of
                  -- we do not want to recurse into the left hand side hence
                  -- we take the original value
                  Ass c _ -> Ass c def
                  _ -> error "handleBinder: impossible case"

            , foldOp = \ _ s epl' args rg' ->
                case lookupBindInfo s $ length args of
                  Just (BindInfo bvl bbl) ->
                       Op s epl' (substBinderArgs bvl bbl args) rg'
                  _ -> Op s epl' args rg'
            , foldList = \ _ l rg' -> List l rg'
            }
    in foldCMD substRec cmd


-- | Transforms Op-Expressions to a set of op-names and a Var-list
varSet :: [EXPRESSION] -> (Set.Set String, [EXPRESSION])
varSet l =
    let opToVar' s (Op v _ _ rg') =
            ( Set.insert (simpleName v) s
            , Var Token{ tokStr = simpleName v, tokPos = rg' } )
        opToVar' _ x =
            error $ "varSet: not supported varexpression " ++ show x
    in mapAccumL opToVar' Set.empty l

-- | Replaces Op occurrences to Var if the op is in the given set
constsToVars :: Set.Set String -> EXPRESSION -> EXPRESSION
constsToVars env e =
    let substRec =
         idRecord
         { foldOp =
            \ _ s epl' args rg' ->
                if Set.member (simpleName s) env then
                    if null args
                    then Var (Token { tokStr = simpleName s, tokPos = rg' })
                    else error $ "constsToVars: variable must not have"
                             ++ " arguments:" ++ show args
                else Op s epl' args rg'
         , foldList = \ _ l rg' -> List l rg'
         }
    in foldTerm substRec e

-- * Utils for 'CMD' and 'EXPRESSION'
subAssignments :: CMD -> [(EXPRESSION, EXPRESSION)]
subAssignments = foldCMD listCMDRecord{ foldAss = \ _ c def -> [(c, def)] }

-- * Further analysis in order to run this specification

-- ** Datatypes and guarded definitions

{- TODO: we want to proceed here as follows:
   1. split the definitions and the program and process the extended parameters
   2. build the dependency relation ( and store it in the signature ?)

   Not checked is:
   1. if all defined symbols have the same arity
-}


-- | A guard consists of the guard range and the corresponding expression
-- together with a name, a set of not propagated parameters and a set of
-- constrained parameters (in the extended parameter specification)
data Guard a = Guard { range :: a
                     , definition :: EXPRESSION
                     , assName :: String
                     , filtered :: Set.Set String
                     , constrained :: Set.Set String }


prettyGuard :: (a -> Doc) -> Guard a -> Doc
prettyGuard f g = f (range g) <+> text "-->" <+> pretty (definition g)

instance Functor Guard where
    fmap f (Guard x e an fs ct) = Guard (f x) e an fs ct

instance Pretty a => Pretty (Guard a) where
    pretty = prettyGuard pretty

instance Pretty a => Show (Guard a) where
    show = show . pretty

-- | A guarded constant consists of the argument list (for function definitions)
-- and a list of guard-expressions
data Guarded a = Guarded { argvars :: [String]
                         , guards :: [Guard a] }

{- Comment it in if needed later

undefinedGuard :: String -> a -> Guard a
undefinedGuard s x = Guard { range = x
                           , definition = err
                           , assName = err
                           , filtered = err
                           , constrained = err }
    where err = error $ "undefinedGuard: " ++ s

undefinedGuarded :: String -> a -> Guarded a
undefinedGuarded s x = Guarded { argvars = []
                               , guards = [undefinedGuard s x] }
-}


prettyGuarded :: (a -> Doc) -> Guarded a -> Doc
prettyGuarded f grdd = vcat $ map (prettyGuard f) $ guards grdd

instance Functor Guarded where
    fmap f grdd = grdd { guards = map (fmap f) $ guards grdd }

instance Pretty a => Pretty (Guarded a) where
    pretty = prettyGuarded pretty

instance Pretty a => Show (Guarded a) where
    show = show . pretty


type GuardedMap a = Map.Map String (Guarded a)


addAssignment :: String -> EXPRESSION -> EXPRESSION -> GuardedMap [EXTPARAM]
              -> GuardedMap [EXTPARAM]
addAssignment n (Op oid@(OpUser _) epl al _) def m =
    let f (Var tok) = tokStr tok
        f x = error $ "addAssignment: not a variable " ++ show x
        combf x y | argvars x == argvars y = y { guards = guards y ++ guards x }
                  | otherwise =
                      error "addAssignment: the argument vars does not match."
        grd = Guarded (map f al) [uncurry (Guard epl def n)
                                              $ filteredConstrainedParams epl]
    in Map.insertWith combf (simpleName oid) grd m

addAssignment _ x _ _ = error $ "unexpected assignment " ++ show x

{-  TODO:
    1. analysis for missing definitions and undeclared extparams
    2. Integrating extparam domain definitions
    3. check for each constant if the Guards exhaust the extparam domain (in splitAS)
-}

-- | Splits the Commands into the AssignmentStore and a program sequence
splitAS :: [Named CMD] -> (GuardedMap [EXTPARAM], [Named CMD])
splitAS cl =
    let f nc (m,l) = case sentence nc of
                       Ass c def -> (addAssignment (senAttr nc) c def m, l)
                       _ -> (m, nc:l)
    in foldr f (Map.empty, []) cl


-- | Transforms the old guards where inclusion overlapping was allowed into
-- disjoint new guards.
analyzeGuarded :: Guarded [EXTPARAM] -> Guarded EPRange
analyzeGuarded x =
    let f grd = (grd, toEPExps $ range grd)
        -- builds a forest mirroring the inclusion relation of the guard ranges
        frst = forestFromEPs f $ guards x
        -- compute the new range information with the disjointness property
        g l rl sf =
            let nodeRg = Atom $ eplabel rl
                newRg = case map (Atom . eplabel . Tr.rootLabel) sf of
                          [] -> nodeRg
                          -- we make nodeRg disjoint with its children
                          -- by removing the union of the children from it
                          rgl -> if isStarEP (eplabel rl)
                                 then Complement $ mkUnion rgl
                                 else Intersection
                                          [nodeRg, Complement $ mkUnion rgl]
            in (nodelabel rl) { range = newRg } : l
        newguards = foldForest g [] frst
    in -- trace (show $ pretty x) $
       x { guards = newguards }

-- | Folds the forest in top-down direction constructing the accumulator
-- from the labels and children of each node.
foldForest :: (b -> a -> Tr.Forest a -> b) -> b -> Tr.Forest a -> b
foldForest f = foldl g where
     g x tr = let sf = Tr.subForest tr
              in foldl g (f x (Tr.rootLabel tr) sf) sf


-- ** Dependency Sorting

-- | Returns a dependency sorted list of constants with their guarded
-- definitions. Requires as input an analyzed Assignment store:
-- @(fmap analyzeGuarded . fst . splitAS)@ produces an adequate input.
dependencySortAS :: GuardedMap EPRange -> [(String, Guarded EPRange)]
dependencySortAS grdm = mapMaybe f $ topsortDirect $ getDependencyRelation grdm
    where f x = fmap ((,) x) $ Map.lookup x grdm


type Rel2 a = Map.Map a (Set.Set a)
type BackRef a = Map.Map a [a]

-- | @r dependsOn r'@ if @r'@ occurs in the definition term of @r@. In this case
-- the set which corresponds to the 'Map.Map' entry of @r@ contains @r'@.
getDependencyRelation :: GuardedMap a -> Rel2 String
getDependencyRelation gm = Map.fold f dr dr where
    f s m = Map.union m $ Map.fromAscList
            $ map (flip (,) Set.empty) $ Set.toAscList s
    dr = Map.map g gm
    g grdd = Set.unions $ map (setOfUserDefined . definition) $ guards grdd

getBackRef :: Ord a => Rel2 a -> BackRef a
getBackRef d =
    let uf k n m  = Map.insertWith (++) n [k] m
        -- for each entry in the set insert k into the list
        f k s m = Set.fold (uf k) m s
    -- from each entry in d add entries in the map
    in Map.foldWithKey f Map.empty d


topsortDirect :: (Show a, Ord a) => Rel2 a -> [a]
topsortDirect d = topsort d $ getBackRef d

-- | This function is based on the Kahn-algorithm. It requires a representation
-- of a relation which has for each entry of the domain an entry in the map.
-- 
-- E.g., 1 |-> {2}, 2 |-> {3, 4} is not allowed because the entries
-- 3 |-> {}, 4 |-> {} are missing
topsort :: (Show a, Ord a) => Rel2 a -> BackRef a -> [a]
topsort d br =
 let f d' acc []
         | Map.null d' = acc
         | otherwise =
             let (s, v) = Map.findMin d'
             in error $ concat [ "topsort: Dependency relation contains cycles "
                               , show s, " -> ", show v ]
     f d' acc (n:l) =
         let cl = Map.findWithDefault [] n br
             (nl, d'') = foldl (remEdge n) ([], d') cl
         in f d'' (acc ++ [n]) $ l ++ nl
     uf n a = let b = Set.delete n a in if Set.null b then Nothing else Just b
     -- returns a new list of empty-nodes and a new def-map
     remEdge n (nl, m) s = let c = Map.size m
                               m' = Map.update (uf n) s m
                           in (if Map.size m' < c then s:nl else nl, m')
     (me, mne) = Map.partition Set.null d
 in f mne [] $ Map.keys me


-- ** Extended Parameter Elimination


{- | 
   Given a dependency ordered list of constant definitions we compute all
   definitions not depending on extended parameter propagation, therefore
   eliminating them. For each constant we produce probably many new constants
   that we call elim-constants. The definition of elim-constant N can be
   looked up in @(guards x)!!N@.
-}
epElimination :: CompareIO m => [(String, Guarded EPRange)]
              -> m [(String, Guarded EPRange)]
epElimination = f Map.empty
    -- for efficient lookup, we build a map in addition to the list containing
    -- the same information

    where
      f _ [] = return []
      f m ((s, g):l) = do
        newguards <- liftM concat $ mapM (eliminateGuard m) $ guards g
        let g' = g{ guards = newguards }
        liftM ((s, g') :) $ f (Map.insert s g' m) l

{- | 
   The given map already contains only elim-constants. We extract the 
   (partly instantiated) constants from the definition in the guard and
   create a partition from their guarded entry in the map. We use
   'refineDefPartitions' to create the refinement and from this we produce
   the new guards.
-}
eliminateGuard :: CompareIO m => GuardedMap EPRange -> Guard EPRange
               -> m [Guard EPRange]
eliminateGuard m grd = do
    let f s epl _ = restrictPartition (range grd)
                    $ case Map.lookup s m of
                        Just grdd -> partitionFromGuarded epl grdd
                        Nothing -> AllPartition 0
        h pim = foldTerm passRecord{ foldOp = const $ mappedElimConst pim }
                $ definition grd
        g (er, pim) = grd{ range = er, definition = h pim }
    logMessage $ "eliminating Guard " ++ assName grd
    partMap <- mapUserDefined f $ definition grd
    rePart <- refineDefPartitions partMap
    case rePart of
      AllPartition x -> return [g (range grd, x)]
      Partition l ->
          -- for each entry in the refined partition create a new guard
          return $ map g l


-- | Helper function of 'eliminateGuard' for substitution of operatornames
-- by mapped entries given in the @'Map.Map' 'PIConst' 'Int'@.
mappedElimConst :: (Map.Map PIConst Int)
                -> OPID  -- ^ the original operator id
                -> [EXTPARAM] -- ^ the extended parameter instantiation
                -> [EXPRESSION] -- ^ the new arguments
                -> Range -- ^ the original range
                -> EXPRESSION
mappedElimConst m oi e al rg = Op newOi [] al rg
    where err = error $ "mappedElimConst: No entry for " ++ show oi
          i = Map.findWithDefault err (mkPIConst (simpleName oi) e) m
          newOi = case oi of
                    OpUser c -> OpUser $ toElimConst c i
                    _ -> oi

-- | Returns the simplified partition representation of the 'Guarded' object
-- probably instantiated by the provided extended parameter list.
partitionFromGuarded :: [EXTPARAM] -> Guarded EPRange -> Partition Int
partitionFromGuarded epl grdd =
    case guards grdd of
      [] -> error "partitionFromGuarded: empty guard list"
      [grd] | isStarRange $ range grd -> AllPartition 0
            | otherwise ->
                error $ "partitionFromGuarded: single guard not exhaustive: "
                      ++ show grd
        
      grds ->
        -- it is crucial here that the zipping takes place with the original guard
        -- list, otherwise the indexes doesn't match their definitions
        Partition $ mapMaybe f $ zip grds [0..] where
            ep = toEPExps epl
            f (a, b) | null epl = Just (range a, b)
                     | otherwise = case projectRange ep $ range a of
                                     Empty -> Nothing
                                     x -> Just (x, b)


-- | A partially instantiated constant
type PIConst = (String, Maybe EPExps)

mkPIConst :: String -> [EXTPARAM] -> PIConst
mkPIConst s epl = (s, if null epl then Nothing else Just $ toEPExps epl)

-- | Returns a map of user defined (partially instantiated) constants
-- to the result of this constant under the given function.
mapUserDefined :: Monad m => (String -> [EXTPARAM] -> [EXPRESSION] -> m a)
                   -> EXPRESSION -> m (Map.Map PIConst a)
mapUserDefined f e = g Map.empty e
    where
      g m x =
       case x of
         Op oi@(OpUser _) epl al _ -> do
             v <- f (simpleName oi) epl al
             let pic = mkPIConst (simpleName oi) epl
                 m' = Map.insert pic v m
             foldM g m' al
         -- handle also non-userdefined ops.
         Op _ _ al _ -> foldM g m al 
         -- ignoring lists (TODO: they should be removed soon anyway)
         _ -> return m

-- | Returns a set of user defined constants ignoring instantiation.
setOfUserDefined :: EXPRESSION -> Set.Set String
setOfUserDefined e = g Set.empty e
    where
      g s x =
       case x of
         Op oi@(OpUser _) _ al _ -> foldl g (Set.insert (simpleName oi) s) al
         -- handle also non-userdefined ops.
         Op _ _ al _ -> foldl g s al 
         -- ignoring lists (TODO: they should be removed soon anyway)
         _ -> s

{- |
   Given a map holding for each constant, probably partly instantiated,
   a partition labeled by the corresponding elim-constants we build a
   partition which refines each of the given partitions labeled by a mapping
   of partly instantiated constants to the corresponding elim-constant
-}
refineDefPartitions :: CompareIO m => Map.Map PIConst (Partition Int)
                    -> m (Partition (Map.Map PIConst Int))
refineDefPartitions =
    foldM refineDefPartition (AllPartition Map.empty) . Map.toList

refineDefPartition :: CompareIO m => Partition (Map.Map PIConst Int)
                   -> (PIConst, Partition Int)
                   -> m (Partition (Map.Map PIConst Int))
refineDefPartition pm (c, ps) = do
    logMessage $ "refining partition for " ++ show c
    liftM (fmap $ uncurry $ Map.insert c) $ refinePartition ps pm


-- * Various Outputs of Guarded Assignments

-- | All in the given AssignmentStore undefined constants
undefinedConstants :: GuardedMap a -> Set.Set String
undefinedConstants gm =
     Map.keysSet
            $ Map.difference (Map.filter Set.null $ getDependencyRelation gm) gm

-- | Turn the output of the elimination procedure into single (unguarded)
--  (probably functional) definitions. Respects the input order of the list.
getElimAS :: [(String, Guarded EPRange)] ->
             [(ConstantName, AssDefinition)]
getElimAS = concatMap f where
    f (s, grdd) = zipWith (g s $ argvars grdd) [0..] $ guards grdd
    g s args i grd = (ElimConstant s i, mkDefinition args $ definition grd)

-- | Return the assignments in output format of 'getElimAS' but for assignments
--  not beeing extended parameter eliminated (for simple specs).
getSimpleAS :: [(String, Guarded EPRange)] ->
             [(ConstantName, AssDefinition)]
getSimpleAS = map f where
    f (s, grdd) =
        case guards grdd of
          [grd] -> g s (argvars grdd) grd
          _ -> error $ "getSimpleAS: only singleton guards supported: "
               ++ show grdd
    g s args grd = (SimpleConstant s, mkDefinition args $ definition grd)

-- | The elim-constant to 'EPRange' mapping.
elimConstants :: [(String, Guarded EPRange)] ->
             [(String, Map.Map ConstantName EPRange)]
elimConstants = map f where
    f (s, grdd) = (s, Map.fromList $ zipWith (g s) [0..] $ guards grdd)
    g s i grd = (ElimConstant s i, range grd)


-- * Dependency Graph datatype for various algorithms on Assignment Graphs

data DepGraph a b = DepGraph
    { dataMap :: Map.Map a
                 ( b         -- the annotation
                 , Set.Set a -- the direct successors (smaller elements)
                 , Set.Set a -- the direct predecessors (bigger elements)
                 )
    -- function returning for a given element and value the predecessors
    -- of this element
    , getPredecessors :: a -> b -> [a]
    }

instance (Show a, Show b) => Show (DepGraph a b) where
    show = show . dataMap

prettyDepGraph :: (a -> Doc) -> (b -> Doc) -> DepGraph a b -> Doc
prettyDepGraph pa pb gr =
    ppMap pa pf ((text "DepGraph" <+>) . braces) vcat f $ dataMap gr where
        f a b = a <> text ":" <+> b
        pf (v, dss, dps) =
            ps dss <+> text " << x << " <+> ps dps <> text ":" <+> pb v
        ps = braces . (sepByCommas . map pa) . Set.toList


instance (Pretty a, Pretty b) => Pretty (DepGraph a b) where
    pretty = prettyDepGraph pretty pretty


emptyDepGraph :: (a -> b -> [a]) -> DepGraph a b
emptyDepGraph f = DepGraph { dataMap = Map.empty, getPredecessors = f }


-- TODO: merge the type Rel2 and DepGraph in order to work only on the
-- new type, and implement a construction of this graph from a list
-- without the necessity to order the elements first.

-- | It is important to have the elements given in an order with
-- biggest elements first (elements which depend on nothing)
depGraphFromDescList :: Ord a => (a -> b -> [a]) -> [(a,b)] -> DepGraph a b
depGraphFromDescList f = foldl g (emptyDepGraph f) where
    g x (y, z) = updateGraph x y z


upperLowerUntilGen :: (a -> (b, [a])) -- ^ follow function and value lookup
                   -> (a -> b -> Bool) -- ^ cut-off predicate
                   -> a -- ^ compare entries to this element
                   -> [(a,b)]
upperLowerUntilGen ff p key = if p key val then [] else combineDepthFirstToBreadthFirst $ map f fups
    where (val, fups) = ff key
          f k = if p k v then [] else (k, v):l
                where (v, fups') = ff k
                      l = combineDepthFirstToBreadthFirst $ map f fups'

combineDepthFirstToBreadthFirst :: [[a]] -> [a]
combineDepthFirstToBreadthFirst ll = uncurry (++) $ f ll where
    f [] = ([], [])
    f ([]:l) = f l
    f ((x:l'):l) = let (hds, tls) = f l in (x:hds, l' ++ tls)

lowerUntil :: (Ord a, Show a) => (a -> b -> Bool) -- ^ cut-off predicate
           -> DepGraph a b -- ^ dependency graph to be traversed
           -> a -- ^ compare entries to this element
           -> [(a,b)]
lowerUntil p gr key = upperLowerUntilGen f p key where
    f k = case Map.lookup k $ dataMap gr of
            Just (v, dss, _) -> (v, Set.toList dss)
            Nothing -> error $ "lowerUntil: No entry for " ++ show k

upperUntil :: (Ord a, Show a) => (a -> b -> Bool) -- ^ cut-off predicate
           -> DepGraph a b -- ^ dependency graph to be traversed
           -> a -- ^ compare entries to this element
           -> [(a,b)]
upperUntil p gr key = upperLowerUntilGen f p key where
    f k = case Map.lookup k $ dataMap gr of
            Just (v, _, dps) -> (v, Set.toList dps)
            Nothing -> error $ "upperUntil: No entry for " ++ show k

updateGraph :: Ord a => DepGraph a b -> a -> b -> DepGraph a b
updateGraph gr key val =
    -- update the pred-set of all smaller entries
    let (mOv, nm) = Map.insertLookupWithKey f key nval $ dataMap gr
        npl = getPredecessors gr key val
        nval = (val, Set.empty, Set.fromList npl)
        f _ (v', _, nps) (_, oss, _) = (v', oss, nps)
        nm' = case mOv of 
                Just (_, _, ops) ->
                    Set.fold rmFromSucc nm ops
                _ -> nm
        nm'' = foldl insSucc nm' npl
        rmFromSucc c m = Map.adjust g1 c m
        g1 (x, dss, dps) = (x, Set.delete key dss, dps)
        insSucc m c = Map.adjust g2 c m
        g2 (x, dss, dps) = (x, Set.insert key dss, dps)
    in gr { dataMap = nm'' }

data DepGraphAnno a = DepGraphAnno
    { annoDef :: AssDefinition
    , annoVal :: a } deriving Show

instance Pretty a => Pretty (DepGraphAnno a) where
    pretty (DepGraphAnno { annoDef = def, annoVal = av }) =
        braces $ pretty def <> text ":" <+> pretty av

type AssignmentDepGraph a = DepGraph ConstantName (DepGraphAnno a)

{-
a = ConstantName
b = (DepGraphAnno a)

getPs : (ConstantName -> (DepGraphAnno a) -> [ConstantName])
map gg l :: [(ConstantName, DepGraphAnno a)]
l :: [(ConstantName, AssDefinition)]
gg :: (ConstantName, AssDefinition) -> (ConstantName, DepGraphAnno a)

depGraphFromDescList :: Ord a => (a -> b -> [a]) -> [(a,b)] -> DepGraph a b
-}
assDepGraphFromDescList :: (ConstantName -> AssDefinition -> a)
                        -> [(ConstantName, AssDefinition)] -> AssignmentDepGraph a
assDepGraphFromDescList f l = depGraphFromDescList getPs $ map g l where
    g (cn, ad) = (cn, DepGraphAnno { annoDef = ad, annoVal = f cn ad })
    getPs _ = map SimpleConstant . Set.toList . setOfUserDefined . getDefiniens . annoDef

   
{-

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a

fold :: (a -> b -> b) -> b -> Set a -> b
                    

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> (Maybe a, Map k a)	Source

O(log n). Combines insert operation with old value retrieval. 
the expression (insertLookupWithKey f k x map) is a pair where
1. element: is equal to (lookup k map) 
2. element: is equal to (insertWithKey f k x map). 


insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a	Source

O(log n). Insert with a function, combining key, new value and old value.

if key does not exist in the map: insertWithKey f key value mp  will insert the pair (key, value) into mp .

if the key does exist: will insert the pair (key,f key new_value old_value).


-- type AssignmentDepGraph = DepGraph ConstantName ()
-}
