{- --------------------------------------------------------------------------
  HetCATS/CASL/Static.hs
  $Id$
  Authors: Pascal Schmidt
  Year:    2002
-----------------------------------------------------------------------------
  SUMMARY
  
  This modules provides static analysis for the BASIC_SPEC datatype
  found in AS_Basic_CASL
   
-----------------------------------------------------------------------------
  TODO

  implement meaningful functions

-------------------------------------------------------------------------- -}

-----------------------------------------------------------------------------
-- Export declarations
-----------------------------------------------------------------------------

module Static where

------------------------------------------------------------------------------
-- Imports from other modules
------------------------------------------------------------------------------

import Maybe
import FiniteMap
import Set
import Id
import AS_Annotation
import GlobalAnnotations
import GlobalAnnotationsFunctions
import AS_Basic_CASL
import Sign
import Result
import Graph
import Latin
import Utils
import Logic ( EndoMap )

------------------------------------------------------------------------------
-- types
------------------------------------------------------------------------------

type Filename = String

data GlobalVars = Global { global :: [VarDecl] }
                  deriving (Eq,Show)

data NamedSentence = NamedSen { senName  :: String,
                                sentence :: Sentence }
                     deriving (Eq,Show)

data Sentences = Sentences { sentences :: [NamedSentence] }
                 deriving (Eq,Show)

data LocalEnv = Env { getName   :: Filename,
                      getGA     :: GlobalAnnos,
                      getSigma  :: Sign,
                      getPsi    :: Sentences,
                      getGlobal :: GlobalVars }

------------------------------------------------------------------------------
-- Functions on signature element
------------------------------------------------------------------------------

emptyGlobal :: GlobalVars
emptyGlobal = Global []

emptySentences :: Sentences
emptySentences = Sentences []

flattenSentences :: Sentences -> [(String, Sentence)]
flattenSentences sens =
  map (\x -> (senName x,sentence x)) (sentences sens)

addNamedSentence :: Sentences -> NamedSentence -> Sentences
addNamedSentence (Sentences l) x = Sentences (setAddOne l x)

myShowList :: Show a => [a] -> String
myShowList []    = "[]"
myShowList [h]   = "'" ++ show h ++ "'"
myShowList (h:t) = "'" ++ (show h) ++ "', " ++ (myShowList t)

emptyLocalEnv :: LocalEnv
emptyLocalEnv =
  Env "empty" emptyGlobalAnnos emptySign emptySentences emptyGlobal

getTokenKind :: String -> TokenKind
getTokenKind s =      if (s==",") then Comma
                 else if (s==";") then Semi
                 else if (s=="<") then Less
                 else if (s=="=") then Equal
                 else if (s==":") then Colon
                 else Key 

getListPos :: (Pos, String) -> ListPos
getListPos (pos,tok) = ListPos (getTokenKind tok) pos

getItemPos :: Filename -> (Pos, String) -> ItemPos
getItemPos name (pos,tok) = ItemPos name (getTokenKind tok) [pos]

hasElem :: Sign -> (Id -> SigItem -> Bool) -> Id -> Bool
hasElem sigma f id =
  let
    res = lookupFM (getMap sigma) id
  in
    if (isJust res) then
      or $ map (f id) (fromJust res)
    else
      False

getElem :: Sign -> (Id -> SigItem -> Bool) -> Id -> Maybe SigItem
getElem sigma f id =
  let
    res = lookupFM (getMap sigma) id
  in
    if (hasElem sigma f id) then
      Just (head $ filter (f id) $ fromJust $ lookupFM (getMap sigma) id)
    else
      Nothing

hasSigSortItem :: Id -> SigItem -> Bool
hasSigSortItem id (ASortItem s) = (sortId $ item s)==id
hasSigSortItem _ _ = False

fromSigSortItem :: Maybe SigItem -> Maybe (Annoted SortItem)
fromSigSortItem (Just (ASortItem s)) = Just s
fromSigSortItem _ = Nothing

hasSort :: Sign -> SortId -> Bool
hasSort sigma id = hasElem sigma hasSigSortItem id

getSort :: Sign -> SortId -> Maybe SigItem
getSort sigma id = getElem sigma hasSigSortItem id

hasSigOpItem :: Id -> SigItem -> Bool
hasSigOpItem id (AnOpItem o) = (opId $ item o)==id
hasSigOpItem _ _ = False

hasOp :: Sign -> Id -> Bool
hasOp sigma id = hasElem sigma hasSigOpItem id

getOp :: Sign -> Id -> Maybe SigItem
getOp sigma id = getElem sigma hasSigOpItem id

hasSigPredItem :: Id -> SigItem -> Bool
hasSigPredItem id (APredItem p) = (predId $ item p)==id
hasSigPredItem _ _ = False

hasPred :: Sign -> Id -> Bool
hasPred sigma id = hasElem sigma hasSigPredItem id

getPred :: Sign -> Id -> Maybe SigItem
getPred sigma id = getElem sigma hasSigPredItem id

cloneAnnos :: Annoted a -> b -> Annoted b
cloneAnnos a b = a { item = b }

mergeAnnos :: Annoted a -> Annoted b -> Annoted b
mergeAnnos a b = b { opt_pos = (opt_pos a) ++ (opt_pos b),
                     l_annos = (l_annos a) ++ (l_annos b),
                     r_annos = (r_annos a) ++ (r_annos b) }

addSuper :: SortRels -> Maybe SortId -> SortRels
addSuper x Nothing = x
addSuper x (Just id) = x { supersorts = setAdd (supersorts x) [id],
                           allsupersrts = setAdd (allsupersrts x) [id] }

addSortItem :: Filename -> Annoted a -> Sign -> SortId -> Maybe SortId
               -> Maybe SortDefn -> (Pos, String) -> Sign
addSortItem name ann sigma id super defn (kwpos,kw) =
  let
    res = fromSigSortItem $ getSort sigma id
    pos = getItemPos name (kwpos,kw)
  in
    if (isJust res) then
      let
        itm = fromJust res
        old = item itm
        new = old { sortDef = if (isJust defn) then defn else (sortDef old),
                    sortPos = pos,
                    sortRels = addSuper (sortRels old) super,
                    altSorts = (altSorts old) ++ [sortPos old] }
      in
        updateSigItem sigma id
                      (ASortItem (mergeAnnos itm (cloneAnnos ann new)))
    else
      let
        new = SortItem id (addSuper emptySortRels super) defn pos []
      in
        updateSigItem sigma id (ASortItem (cloneAnnos ann new))

updateSigItem :: Sign -> Id -> SigItem -> Sign
updateSigItem (SignAsMap m g) id itm =
  let
    res = lookupFM m id
  in
    if (isNothing res) then
      SignAsMap (addToFM m id [itm]) g
    else
      let
        lst = fromJust res
        new = [ x | x<-lst, x /= itm ] ++ [itm]
      in
        SignAsMap (addToFM m id new) g

addSubSort :: Bool -> SortId -> Sign -> SortId -> Sign
addSubSort direct sub sigma super =
  let
    res = fromJust $ fromSigSortItem $ getSort sigma super
    old = sortRels $ item res
    new = if (direct) then
            old { subsorts = setAdd (subsorts old) [sub],
                  allsubsrts = setAdd (allsubsrts old) [sub] }
          else
            old { allsubsrts = setAdd (allsubsrts old) [sub] }
    ext  = (item res) { sortRels = new }
    s'  = updateSigItem sigma super (ASortItem (res { item = ext }))
    s'' = chain s' (addSubSort False sub) (allsupersrts old)
  in
    chain s'' (addSuperSorts (allsupersrts old)) (allsubsrts old)
    
addSuperSorts :: [SortId] -> Sign -> SortId -> Sign
addSuperSorts supers sigma sub =
  let
    res = fromJust $ fromSigSortItem $ getSort sigma sub
    old = sortRels $ item res
    new = old { allsupersrts = setAdd (allsupersrts old) supers }
    ext = (item res) { sortRels = new }
  in
    updateSigItem sigma sub (ASortItem (res { item = ext }))

chainPos' :: LocalEnv -> (LocalEnv -> a -> (Pos, String) -> Result LocalEnv)
             -> [a] -> [(Pos,String)] -> Result LocalEnv
chainPos' env f [] [] = return env
chainPos' env f [] (h:t) = return env
chainPos' env f (a:as) (p:ps) =
  do env' <- f env a p
     chainPos' env' f as ps

-- given a signature, chain through a list of items taking care of
--   passing positions and tokens to subfunctions
-- arguments:
--  sigma: input signature
--      f: function to run on individual items
--    itm: list of items to traverse in order
--     ps: position and token list from higher level item if needed
--    pos: position list that comes with itm
--     pf: function that can turn the position into tokens
--
chainPos :: LocalEnv -> (LocalEnv -> a -> (Pos, String) -> Result LocalEnv)
            -> [a] -> [(Pos,String)] -> [Pos] -> ([Pos] -> [String])
            -> Result LocalEnv
chainPos env f itm ps pos pf =
  chainPos' env f itm (ps ++ (zip pos (pf pos)))

chain :: Sign -> (Sign -> a -> Sign) -> [a] -> Sign
chain sigma f l = foldl f sigma l

genSemi :: [Pos] -> [String]
genSemi [] = []
genSemi (h:t) = ";":(genSemi t)

genComma :: [Pos] -> [String]
genComma [] = []
genComma (h:t) = ",":(genComma t)

genColon :: [Pos] -> [String]
genColon [] = []
genColon (h:t) = ":":(genColon t)

strPosSORT_ITEM :: [Pos] -> [String]
strPosSORT_ITEM [] = []
strPosSORT_ITEM (h:t) = "sorts":(genSemi t)

strPosSortDecl :: [Pos] -> [String]
strPosSortDecl = genComma

strPosSubsortDecl :: [Pos] -> [String]
strPosSubsortDecl l = (genComma $ init l) ++ ["<"]

strPosSubsortDefn :: [Pos] -> [String]
strPosSubsortDefn _ = ["=","{",":",".","}"]

addSortDecl :: Annoted SORT_ITEM -> LocalEnv -> SORT -> (Pos, String)
               -> Result LocalEnv
addSortDecl itm env sort pos =
  return
  env { getSigma =
        (addSortItem (getName env) itm (getSigma env) sort Nothing Nothing pos) }

checkSubDistinctSuper :: LocalEnv -> Pos -> SORT -> SORT -> Result LocalEnv
checkSubDistinctSuper env pos sub super =
  if (super /= sub) then
    return env
  else
    fatal_error "subsort not distinct from supersort"
                pos

addSubsortDecl :: Annoted SORT_ITEM -> Maybe SortDefn -> SORT -> LocalEnv
                  -> SORT -> (Pos, String) -> Result LocalEnv
addSubsortDecl itm defn super env sub pos =
  do env' <- checkSubDistinctSuper env (fst pos) super sub
     let res = addSortItem (getName env) itm (getSigma env') sub (Just super) defn pos
     return env' { getSigma = res }

toVarDecl :: VAR -> SortId -> Pos -> VarDecl
toVarDecl var id pos = VarDecl var id (ListPos Colon pos)

-- FIXME
--
toFormula :: LocalEnv -> Annoted FORMULA -> Formula
toFormula env f = TrueAtom []

-- FIXME
--
toAnnotedFormula :: LocalEnv -> Annoted FORMULA -> Annoted Formula
toAnnotedFormula env f = cloneAnnos f (toFormula env f)

toNamedSentence :: LocalEnv -> String -> Annoted Formula -> NamedSentence
toNamedSentence env str f =
  NamedSen str
    (Axiom (cloneAnnos f (AxiomDecl (global $ getGlobal env) (item f) [])))

checkSortExists :: LocalEnv -> Pos -> SORT -> Result LocalEnv
checkSortExists env pos sort =
  if ((getSigma env) `hasSort` sort) then
    return env
  else
    fatal_error ("sort '"++(show sort)++"' is not declared") pos

-- create some label from Annoted type
--  if it has Label anno, use that, else use a generated default label
--
someLabel :: (b -> String) -> b -> Annoted a -> String
someLabel defaultfun defaultargs x =
  let
    labels = filter (\x -> case x of (Label s p) -> True;
                                               _ -> False)
                    ((l_annos x)++(r_annos x))
  in
    case labels of ((Label s p):t) -> concat s;
                                 _ -> defaultfun defaultargs

genLabel :: Show a => a -> String
genLabel x = toASCII $ show x

subsortLabel :: (SORT, SORT) -> String
subsortLabel (sub,super) = "ga_subsort_defn_" ++ (genLabel sub) ++ "_"
                           ++ (show super) ++ "_"

addSubsortFormula :: LocalEnv -> Pos -> VAR -> SORT -> SORT -> Annoted FORMULA
                     -> Result LocalEnv
addSubsortFormula env colpos var sub super f =
  let
    f' = cloneAnnos f (Quantification Universal [(Var_decl [var] super
                        [colpos])] (Equivalence (item f) (Membership
                        (Simple_id var) sub []) []) [])
  in
    return env { getPsi = addNamedSentence (getPsi env)
                          (toNamedSentence env (someLabel
                                                subsortLabel (sub,super) f')
                          (toAnnotedFormula env f')) }

addSubsortDefn :: Annoted SORT_ITEM -> LocalEnv -> SORT -> VAR -> SORT
                  -> Annoted FORMULA -> (Pos, String) -> [Pos]
                  -> Result LocalEnv
addSubsortDefn itm env sub var super f (pos,token) p =
  let
    colpos = head $ drop 2 p
    defn   = SubsortDefn (toVarDecl var super colpos) (toFormula env f) p
  in
    do env'   <- checkSortExists env pos super
       env''  <- checkSubDistinctSuper env' pos sub super
       env''' <- addSubsortDecl itm (Just defn) super env sub (pos,token)
       addSubsortFormula env''' colpos var sub super f

addIsoSubsorting :: [SORT] -> Sign -> SORT -> Sign
addIsoSubsorting isos sigma iso =
  let
    others = [ x | x<-isos, x/=iso ]
    res    = fromJust $ fromSigSortItem $ getSort sigma iso
    old    = sortRels $ item res
    new    = old { subsorts = setAdd (subsorts old) others,
                   supersorts = setAdd (supersorts old) others,
                   allsubsrts = setAdd (allsubsrts old) others,
                   allsupersrts = setAdd (allsupersrts old) others }
    ext     = (item res) { sortRels = new }
  in
    updateSigItem sigma iso (ASortItem (res { item = ext }))

checkAllUnique :: LocalEnv -> Pos -> [SORT] -> Result LocalEnv
checkAllUnique env pos sorts =
  if (allUnique sorts) then
    return env
  else
    fatal_error ("multiple occurences of sort(s): "
                 ++(myShowList $ notUnique sorts)) pos

checkMoreThanOne :: LocalEnv -> Pos -> [SORT] -> Result LocalEnv
checkMoreThanOne env pos sorts =
  if ((length sorts)>=2) then
    return env
  else
    fatal_error "single sort in isomorphism decl" pos

addIsoDecl :: Annoted SORT_ITEM -> LocalEnv -> [SORT] -> (Pos, String)
                -> [Pos] -> Result LocalEnv
addIsoDecl itm env sorts pos p =
  do env'   <- checkAllUnique env (fst pos) sorts
     env''  <- checkMoreThanOne env (fst pos) sorts
     env''' <- chainPos env'' (addSortDecl itm) sorts [pos]
                        p strPosIsoDecl
     return env''' { getSigma = foldl (addIsoSubsorting sorts)
                                (getSigma env''') sorts }

strPosIsoDecl :: [Pos] -> [String]
strPosIsoDecl = genColon

addSORT_ITEM :: LocalEnv -> Annoted SORT_ITEM -> (Pos, String)
                 -> Result LocalEnv
addSORT_ITEM env itm pos =
  case (item itm) of
    (Sort_decl l p)          -> chainPos env (addSortDecl itm) l [pos] p
                                         strPosSortDecl;
    (Subsort_decl l s p)     -> chainPos env (addSubsortDecl itm Nothing s)
                                         l [pos] p strPosSubsortDecl;
    (Subsort_defn s v t f p) -> addSubsortDefn itm env s v t f pos p;
    (Iso_decl l p)           -> addIsoDecl itm env l pos p

addSIG_ITEMS :: LocalEnv -> SIG_ITEMS -> Result LocalEnv
addSIG_ITEMS env (Sort_items l p) = chainPos env addSORT_ITEM l 
                                              [] p strPosSORT_ITEM
addSIG_ITEMS env (Op_items _ p) = return env
addSIG_ITEMS env (Pred_items _ p) = return env
addSIG_ITEMS env (Datatype_items _ p) = return env

strPosVarItems :: [Pos] -> [String]
strPosVarItems [] = []
strPosVarItems (h:t) = "var":(genSemi t)

addBASIC_SPEC :: LocalEnv -> BASIC_SPEC -> Result LocalEnv
addBASIC_SPEC env (Basic_spec l) = foldResult env addBASIC_ITEMS l

addBASIC_ITEMS :: LocalEnv -> Annoted BASIC_ITEMS -> Result LocalEnv
addBASIC_ITEMS env itm =
  case (item itm) of
    (Sig_items s) -> addSIG_ITEMS env s;
    (Free_datatype l p) -> return env;
    (Sort_gen s p) -> return env;
    (Var_items v p) -> chainPos env addVarItems v [] (tail p)
                                strPosVarItems;
    (Local_var_axioms v f p) -> return env;
    (Axiom_items f p) -> return env

addVarItems :: LocalEnv -> VAR_DECL -> (Pos, String) -> Result LocalEnv
addVarItems env (Var_decl v s p) pos =
  chainPos env (addVAR_DECL s) v [] p strPosVAR_DECL

strPosVAR_DECL :: [Pos] -> [String]
strPosVAR_DECL []  = []
strPosVAR_DECL [h] = [":"]
strPosVAR_DECL l   = genComma (init l) ++ [":"]

addVAR_DECL :: SORT -> LocalEnv -> VAR -> (Pos, String) -> Result LocalEnv
addVAR_DECL s env v pos =
  do env' <- checkSortExists env (fst pos) s
     return env' { getGlobal = Global (setAddOne (global $ getGlobal env')
                               (VarDecl v s (getListPos pos))) }

basic_analysis :: (BASIC_SPEC, Sign, GlobalAnnos)
                  -> Result (Sign,Sign,[(String,Sentence)])
basic_analysis (b,sigma,ga) =
  do env <- addBASIC_SPEC
            (Env "unknown" ga sigma emptySentences emptyGlobal) b
     let sigma' = getSigma env
     let delta  = signDiff sigma sigma'
     return (delta,sigma',flattenSentences $ getPsi env)

-- FIXME
--
signDiff :: Sign -> Sign -> Sign
signDiff a b = b

symbTypeToKind :: SymbType -> Kind
symbTypeToKind (OpAsItemType optype) = FunKind
symbTypeToKind (PredType predtype)   = PredKind
symbTypeToKind (Sign.Sort)           = SortKind

symbolToRaw :: Symbol -> RawSymbol
symbolToRaw (Symbol id typ) = AKindedId (symbTypeToKind typ) id

idToRaw :: Id -> RawSymbol
idToRaw x = AnID x

sigItemToSymbol :: SigItem -> Symbol
sigItemToSymbol (ASortItem s) = Symbol (sortId $ item s) Sign.Sort
sigItemToSymbol (AnOpItem  o) = Symbol (opId $ item o)
                                       (OpAsItemType (opType $ item o))
sigItemToSymbol (APredItem p) = Symbol (predId $ item p)
                                       (PredType (predType $ item p))

symOf :: Sign -> Set Symbol
symOf sigma = mkSet $ map sigItemToSymbol $ concat $ eltsFM $ getMap sigma

idToSortSymbol :: Id -> Symbol
idToSortSymbol id = Symbol id Sign.Sort

idToOpSymbol :: Id -> OpType -> Symbol
idToOpSymbol id typ = Symbol id (OpAsItemType typ)

idToPredSymbol :: Id -> PredType -> Symbol
idToPredSymbol id typ = Symbol id (PredType typ)

funMapEntryToSymbol :: Sign -> (Id,[(OpType,Id,Bool)]) -> [(Symbol,Symbol)]
funMapEntryToSymbol sigma (id,[]) = []
funMapEntryToSymbol sigma (id,(typ,newId,_):t) =
  let
    origType = opType $ (\x -> case x of (AnOpItem o) -> item o)
                      $ fromJust $ getOp sigma id
  in
    (idToOpSymbol id origType,idToOpSymbol newId typ):
    (funMapEntryToSymbol sigma (id,t)) 

predMapEntryToSymbol :: Sign -> (Id,[(PredType,Id)]) -> [(Symbol,Symbol)]
predMapEntryToSymbol sigma (id,[]) = []
predMapEntryToSymbol sigma (id,(typ,newId):t) =
  let
    origType = predType $ (\x -> case x of (APredItem p) -> item p)
                        $ fromJust $ getPred sigma id
  in
    (idToPredSymbol id origType,idToPredSymbol newId typ):
    (predMapEntryToSymbol sigma (id,t))

symmapOf :: Morphism -> EndoMap Symbol
symmapOf (Morphism src trg sorts funs preds) =
  let
    sortMap = listToFM $ zip (map idToSortSymbol $ keysFM sorts)
                             (map idToSortSymbol $ eltsFM sorts)
    funMap  = listToFM $ concat $ map (funMapEntryToSymbol src)
                                      (fmToList funs)
    predMap = listToFM $ concat $ map (predMapEntryToSymbol src)
                                      (fmToList preds)
  in
    foldl plusFM emptyFM [sortMap,funMap,predMap]

matches :: Symbol -> RawSymbol -> Bool
matches x                            (ASymbol y)             =  x==y
matches (Symbol id _)                (AnID di)               = id==di
matches (Symbol id Sign.Sort)        (AKindedId SortKind di) = id==di
matches (Symbol id (OpAsItemType _)) (AKindedId FunKind di)  = id==di
matches (Symbol id (PredType _))     (AKindedId PredKind di) = id==di
matches _                            _                       = False

symName :: Symbol -> Id
symName (Symbol id _) = id

statSymbMapItems :: SYMB_MAP_ITEMS -> Result (EndoMap RawSymbol)
statSymbMapItems (Symb_map_items kind l _) =
  return (listToFM $ map (symbOrMapToRaw kind) l)
  
symbOrMapToRaw :: SYMB_KIND -> SYMB_OR_MAP -> (RawSymbol,RawSymbol)
symbOrMapToRaw k (Symb s) = (symbToRaw k s,symbToRaw k s)
symbOrMapToRaw k (Symb_map s t _) = (symbToRaw k s,symbToRaw k t)

statSymbItems :: SYMB_ITEMS -> Result [RawSymbol]
statSymbItems (Symb_items kind l _) =
  return (map (symbToRaw kind) l)

symbToRaw :: SYMB_KIND -> SYMB -> RawSymbol
symbToRaw k (Symb_id id)       = symbKindToRaw k id
symbToRaw k (Qual_id id typ _) = symbKindToRaw k id

symbKindToRaw :: SYMB_KIND -> Id -> RawSymbol
symbKindToRaw Implicit     id = AnID id
symbKindToRaw (Sorts_kind) id = AKindedId SortKind id
symbKindToRaw (Ops_kind)   id = AKindedId FunKind  id
symbKindToRaw (Preds_kind) id = AKindedId PredKind id

typeToRaw :: SYMB_KIND -> TYPE -> Id -> RawSymbol
typeToRaw k (O_type _) id = AKindedId FunKind  id
typeToRaw k (P_type _) id = AKindedId PredKind id
typeToRaw k (A_type _) id = symbKindToRaw k id

checkItem :: Sign -> (Id,SigItem) -> Bool
checkItem sigma (id,si) =
  let
    res   = lookupFM (getMap sigma) id
    items = if (isJust res) then
              fromJust res
            else
              []
  in
    si `elem` items

unfoldSigItems :: (Id, [SigItem]) -> [(Id, SigItem)]
unfoldSigItems (id,[])  = []
unfoldSigItems (id,h:t) = (id,h):(unfoldSigItems (id,t))

isSubSig :: Sign -> Sign -> Bool
isSubSig sub super =
  and $ map (checkItem super) $ concat $ map unfoldSigItems
      $ fmToList $ getMap sub

------------------------------------------------------------------------------
-- THE END
------------------------------------------------------------------------------
