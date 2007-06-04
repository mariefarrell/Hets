{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

analyse type declarations
-}

module HasCASL.TypeDecl where

import Data.Maybe

import Common.Id
import Common.AS_Annotation
import Common.Lib.State
import qualified Data.Map as Map
import Common.Result
import Common.GlobalAnnotations

import HasCASL.As
import HasCASL.AsUtils
import HasCASL.Le
import HasCASL.ClassAna
import HasCASL.TypeAna
import HasCASL.ConvertTypePattern
import HasCASL.DataAna
import HasCASL.Unify
import HasCASL.VarDecl
import HasCASL.SubtypeDecl
import HasCASL.MixAna
import HasCASL.TypeCheck

anaFormula :: GlobalAnnos -> Annoted Term
           -> State Env (Maybe (Annoted Term, Annoted Term))
anaFormula ga at =
    do rt <- resolve ga $ item at
       case rt of
         Nothing -> return Nothing
         Just t -> do
           mt <- typeCheck (Just unitType) t
           return $ case mt of
             Nothing -> Nothing
             Just e -> Just (at { item = t }, at { item = e })

anaVars :: TypeEnv -> Vars -> Type -> Result [VarDecl]
anaVars _ (Var v) t = return [VarDecl v t Other nullRange]
anaVars te (VarTuple vs _) t =
    let (topTy, ts) = getTypeAppl t
        n = length ts
    in if n > 1 && lesserType te topTy (toType $ productId n) then
               if n == length vs then
                  let lrs = zipWith (anaVars te) vs ts
                      lms = map maybeResult lrs in
                      if all isJust lms then
                         return $ concatMap fromJust lms
                         else Result (concatMap diags lrs) Nothing
               else mkError "wrong arity" topTy
        else mkError "product type expected" topTy

mapAnMaybe :: (Monad m) => (a -> m (Maybe b)) -> [Annoted a] -> m [Annoted b]
mapAnMaybe f al =
    do il <- mapAnM f al
       return $ map ( \ a -> replaceAnnoted (fromJust $ item a) a) $
              filter (isJust . item) il

anaTypeItems :: GlobalAnnos -> GenKind -> Instance -> [Annoted TypeItem]
            -> State Env [Annoted TypeItem]
anaTypeItems ga gk inst l = do
    ul <- mapAnMaybe ana1TypeItem l
    tys <- mapM ( \ (Datatype d) -> dataPatToType d) $
              filter ( \ t -> case t of
                       Datatype _ -> True
                       _ -> False) $ map item ul
    rl <- mapAnMaybe (anaTypeItem ga gk inst tys) ul
    addDataSen tys
    return rl

addDataSen :: [DataPat] -> State Env ()
addDataSen tys = do
    tm <- gets typeMap
    let tis = map ( \ (DataPat i _ _ _) -> i) tys
        ds = foldr ( \ i dl -> case Map.lookup i tm of
                     Nothing -> dl
                     Just ti -> case typeDefn ti of
                                DatatypeDefn dd -> dd : dl
                                _ -> dl) [] tis
        sen = (makeNamed ("ga_" ++ showSepList (showString "_") showId tis "")
              $ DatatypeSen ds) { isDef = True }
    if null tys then return () else appendSentences [sen]

ana1TypeItem :: TypeItem -> State Env (Maybe TypeItem)
ana1TypeItem (Datatype d) =
    do md <- ana1Datatype d
       return $ fmap Datatype md
ana1TypeItem t = return $ Just t

-- | analyse a 'TypeItem'
anaTypeItem :: GlobalAnnos -> GenKind -> Instance -> [DataPat] -> TypeItem
            -> State Env (Maybe TypeItem)
anaTypeItem _ _ inst _ (TypeDecl pats kind ps) =
    do cm <- gets classMap
       let Result cs (Just rrk) = anaKindM kind cm
           Result ds (Just is) = convertTypePatterns pats
       addDiags $ cs ++ ds
       let (rk, ak) = if null cs then (rrk, kind) else (rStar, universe)
       mis <- mapM (addTypePattern NoTypeDefn inst (rk, [ak])) is
       let newPats = map toTypePattern $ catMaybes mis
       return $ if null newPats then Nothing else
              Just $ TypeDecl newPats ak ps

anaTypeItem _ _ inst _ (SubtypeDecl pats t ps) =
    do let Result ds (Just is) = convertTypePatterns pats
       addDiags ds
       te <- get
       let Result es mp = anaTypeM (Nothing, t) te
       case mp of
           Nothing -> do
               mis <- mapM (addTypePattern NoTypeDefn inst
                            (rStar, [universe])) is
               let nis = catMaybes mis
                   newPats = map toTypePattern nis
               if null newPats then return Nothing else case t of
                   TypeToken tt -> do
                       let tid = simpleIdToId tt
                           newT = TypeName tid rStar 0
                       addTypeId False NoTypeDefn inst rStar universe tid
                       mapM_ (addSuperType newT universe) nis
                       return $ Just $ SubtypeDecl newPats newT ps
                   _ -> do
                       addDiags es
                       return $ Just $ TypeDecl newPats universe ps
           Just (ak@(rk, _), newT) -> do
              mis <- mapM (addTypePattern NoTypeDefn inst ak) is
              let nis = catMaybes mis
              mapM_ (addSuperType newT $ rawToKind rk) nis
              return $ if null nis then Nothing else
                     Just $ SubtypeDecl (map toTypePattern nis) newT ps

anaTypeItem _ _ inst _ (IsoDecl pats ps) =
    do let Result ds (Just is) = convertTypePatterns pats
       addDiags ds
       mis <- mapM (addTypePattern NoTypeDefn inst (rStar, [universe])) is
       let nis = catMaybes mis
       mapM_ ( \ i -> mapM_ (addSuperType (TypeName i rStar 0)
                                          universe) nis) $ map fst nis
       return $ if null nis then Nothing else
              Just $ IsoDecl (map toTypePattern nis) ps

anaTypeItem ga _ inst _ (SubtypeDefn pat v t f ps) =
    do let Result ds m = convertTypePattern pat
       addDiags ds
       case m of
           Nothing -> return Nothing
           Just (i, tArgs) -> do
               tvs <- gets localTypeVars
               newAs <- mapM anaddTypeVarDecl tArgs
               mt <- anaStarType t
               let nAs = catMaybes newAs
                   newPat = TypePattern i nAs nullRange
               case mt of
                   Nothing -> do
                       putLocalTypeVars tvs
                       return Nothing
                   Just ty -> do
--                       newPty <- generalizeT $ TypeScheme nAs ty nullRange
                       let fullKind = typeArgsListToKind nAs universe
                       rk <- anaKind fullKind
                       e <- get
                       let Result es mvds = anaVars e v $ monoType ty
                           altAct = do
                               putLocalTypeVars tvs
                               return Nothing
                       addDiags es
                       if cyclicType i ty then do
                           addDiags [mkDiag Error
                                     "illegal recursive subtype definition" ty]
                           putLocalTypeVars tvs
                           return Nothing
                           else case mvds of
                           Nothing -> altAct
                           Just vds -> do
                               checkUniqueVars vds
                               vs <- gets localVars
                               mapM_ (addLocalVar True) vds
                               mf <- anaFormula ga f
                               putLocalVars vs
                               case mf of
                                   Nothing -> altAct
                                   Just (newF, _) -> do
                                       addTypeId True NoTypeDefn
 --  (Supertype v newPty  $ item newF)
                                           inst rk fullKind i
 -- add a corresponding equation
                                       addSuperType ty universe (i, nAs)
                                       putLocalTypeVars tvs
                                       return $ Just $ SubtypeDefn newPat v ty
                                              newF ps

anaTypeItem _ _ inst _ (AliasType pat mk sc ps) =
    do let Result ds m = convertTypePattern pat
       addDiags ds
       case m of
              Nothing -> return Nothing
              Just (i, tArgs) -> do
                  tvs <- gets localTypeVars -- save variables
                  newAs <- mapM anaddTypeVarDecl tArgs
                  (ik, mt) <- anaPseudoType mk sc
                  let nAs = catMaybes newAs
                  case mt of
                          Nothing -> do putLocalTypeVars tvs
                                        return Nothing
                          Just (TypeScheme args ty qs) ->
                              if cyclicType i ty then
                                do addDiags [mkDiag Error
                                       "illegal recursive type synonym" ty]
                                   putLocalTypeVars tvs
                                   return Nothing
                                else do
                                let allArgs = nAs++args
                                    fullKind = typeArgsListToKind nAs ik
                                    allSc = TypeScheme allArgs ty qs
                                rk <- anaKind fullKind
                                newPty <- generalizeT allSc
                                putLocalTypeVars tvs
                                b <- addTypeId True (AliasTypeDefn newPty)
                                        inst rk fullKind i
                                return $ if b then Just $ AliasType
                                           (TypePattern i [] nullRange)
                                           (Just fullKind) newPty ps
                                         else Nothing

anaTypeItem _ gk inst tys (Datatype d) =
    do mD <- anaDatatype gk inst tys d
       case mD of
           Nothing -> return Nothing
           Just newD -> return $ Just $ Datatype newD

ana1Datatype :: DatatypeDecl -> State Env (Maybe DatatypeDecl)
ana1Datatype (DatatypeDecl pat kind alts derivs ps) =
    do cm <- gets classMap
       let Result cs (Just rk) = anaKindM kind cm
           k = if null cs then kind else universe
       addDiags $ checkKinds pat rStar rk ++ cs
       let rms = map ( \ c -> anaKindM (ClassKind c) cm) derivs
           mcs = map maybeResult rms
           jcs = catMaybes mcs
           newDerivs = map fst $ filter (isJust . snd) $ zip derivs mcs
           Result ds m = convertTypePattern pat
       addDiags (ds ++ concatMap diags rms)
       addDiags $ concatMap (checkKinds pat rStar) jcs
       case m of
              Nothing -> return Nothing
              Just (i, tArgs) -> do
                  tvs <- gets localTypeVars
                  newAs <- mapM anaddTypeVarDecl tArgs
                  putLocalTypeVars tvs
                  let nAs = catMaybes newAs
                      fullKind = typeArgsListToKind nAs k
                  addDiags $ checkUniqueTypevars nAs
                  frk <- anaKind fullKind
                  b <- addTypeId False PreDatatype Plain frk fullKind i
                  return $ if b then Just $ DatatypeDecl
                    (TypePattern i nAs nullRange) k alts newDerivs ps
                    else Nothing

dataPatToType :: DatatypeDecl -> State Env DataPat
dataPatToType (DatatypeDecl (TypePattern i nAs _) k _ _ _) = do
     rk <- anaKind k
     return $ DataPat i nAs rk $ patToType i nAs rk
dataPatToType _ = error "dataPatToType"

addDataSubtype :: DataPat -> Kind -> Type -> State Env ()
addDataSubtype (DataPat _ nAs _ rt) k st =
    case st of
    TypeName i _ _ -> addSuperType rt k (i, nAs)
    _ -> addDiags [mkDiag Warning "data subtype ignored" st]

-- | analyse a 'DatatypeDecl'
anaDatatype :: GenKind -> Instance -> [DataPat]
            -> DatatypeDecl -> State Env (Maybe DatatypeDecl)
anaDatatype genKind inst tys
       d@(DatatypeDecl (TypePattern i nAs _) k alts _ _) =
    do dt@(DataPat _ _ rk rt) <- dataPatToType d
       let fullKind = typeArgsListToKind nAs k
       frk <- anaKind fullKind
       tvs <- gets localTypeVars
       mapM_ (addTypeVarDecl False) nAs
       mNewAlts <- fromResult $ anaAlts tys dt (map item alts)
       case mNewAlts of
         Nothing -> do
             putLocalTypeVars tvs
             return Nothing
         Just newAlts -> do
           mapM_ (addDataSubtype dt fullKind) $ foldr
             ( \ (Construct mc ts _ _) l -> case mc of
               Nothing -> ts ++ l
               Just _ -> l) [] newAlts
           let srt = generalize nAs rt
           mapM_ ( \ (Construct mc tc p sels) -> case mc of
               Nothing -> return ()
               Just c -> do
                   let sc = TypeScheme nAs
                         (getFunType srt p tc) nullRange
                   addOpId c sc [] (ConstructData i)
                   mapM_ ( \ (Select ms ts pa) -> case ms of
                           Just s -> do
                               let selSc = TypeScheme nAs
                                        (getSelType srt pa ts) nullRange
                               addOpId s selSc []
                                       $ SelectData [ConstrInfo c sc] i
                           Nothing -> return False) $ concat sels) newAlts
           let de = DataEntry Map.empty i genKind (genTypeArgs nAs) rk newAlts
           addTypeId True (DatatypeDefn de) inst frk fullKind i
           appendSentences $ makeDataSelEqs de srt
           putLocalTypeVars tvs
           return $ Just d
anaDatatype _ _ _ _ = error "anaDatatype (not preprocessed)"

-- | analyse a pseudo type (represented as a 'TypeScheme')
anaPseudoType :: Maybe Kind -> TypeScheme -> State Env (Kind, Maybe TypeScheme)
anaPseudoType mk (TypeScheme tArgs ty p) =
    do cm <- gets classMap
       let k = case mk of
            Nothing -> Nothing
            Just j -> let Result cs _ = anaKindM j cm
                      in Just $ if null cs then j else universe
       nAs <- mapM anaddTypeVarDecl tArgs
       let ntArgs = catMaybes nAs
       mp <- anaType (Nothing, ty)
       case mp of
           Nothing -> return ( universe, Nothing)
           Just ((_, sks), newTy) -> case sks of
               [sk] -> do
                   let newK = typeArgsListToKind ntArgs sk
                   irk <- anaKind newK
                   case k of
                     Nothing -> return ()
                     Just j -> do grk <- anaKind j
                                  addDiags $ checkKinds ty grk irk
                   return (newK, Just $ TypeScheme ntArgs newTy p)
               _ -> return ( universe, Nothing)

-- | add a type pattern
addTypePattern :: TypeDefn -> Instance -> (RawKind, [Kind])
               -> (Id, [TypeArg])  -> State Env (Maybe (Id, [TypeArg]))

addTypePattern defn inst (_, ks) (i, tArgs) =
    nonUniqueKind ks i $ \ kind -> do
       tvs <- gets localTypeVars
       newAs <- mapM anaddTypeVarDecl tArgs
       let nAs = catMaybes newAs
           fullKind = typeArgsListToKind nAs kind
       putLocalTypeVars tvs
       addDiags $ checkUniqueTypevars nAs
       frk <- anaKind fullKind
       b <- addTypeId True defn inst frk fullKind i
       return $ if b then Just (i, nAs) else Nothing
