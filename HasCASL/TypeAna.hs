
{- HetCATS/HasCASL/TypeAna.hs
   $Id$
   Authors: Christian Maeder
   Year:    2003
   
   analyse given classes and types
-}

module HasCASL.TypeAna where

import HasCASL.As
import HasCASL.AsUtils
import HasCASL.ClassAna
import Common.Id
import HasCASL.Le
import Data.List
import Data.Maybe
import Control.Monad.State
import HasCASL.PrintAs(showPretty)
import qualified Common.Lib.Map as Map
import Common.Result

data ApplMode = OnlyArg | TopLevel 

mkTypeConstrAppls :: ApplMode -> Type -> State Env Type
mkTypeConstrAppls _ t@(TypeName _ _ _) = 
       return t 

mkTypeConstrAppls m (TypeAppl t1 t2) = 
    do t3 <- mkTypeConstrAppls m t1
       t4 <- mkTypeConstrAppls OnlyArg t2
       return $ TypeAppl t3 t4 

mkTypeConstrAppls _ (TypeToken t) = 
    do let i = simpleIdToId t
       tk <- getTypeMap
       let m = getKind tk i
	   c = if isTypeVar tk i then 1 else 0
       case m of 
	      Just k -> return $ TypeName i k c 
	      _ -> return $ TypeToken t

mkTypeConstrAppls m t@(BracketType b ts ps) =
    do args <- mapM (mkTypeConstrAppls m) ts
       let toks@[o,c] = mkBracketToken b ps 
	   i = if null ts then Id toks [] [] 
	       else Id [o, Token place $ posOfType $ head ts, c] [] []
       tk <- getTypeMap 
       let mk = getKind tk i
	   n = case mk of Just k -> TypeName i k 0
			  _ -> t
	   ds = [Diag Error ("illegal type: " ++ showPretty t "")
		$ posOfType t]
       if null ts then return n
	  else if null $ tail ts 
	       then return $ case b of 
			   Parens -> head args 
			   _ -> TypeAppl n (head args)
	       else do case m of 
			      TopLevel -> appendDiags ds
			      OnlyArg -> case b of 
						Parens -> return ()
						_ -> appendDiags ds
		       return $ BracketType b args ps

mkTypeConstrAppls _ (MixfixType []) = error "mkTypeConstrAppl (MixfixType [])"
mkTypeConstrAppls _ (MixfixType (f:a)) =
   do newF <- mkTypeConstrAppls TopLevel f 
      newA <- mapM (mkTypeConstrAppls OnlyArg) a
      return $ foldl1 TypeAppl $ newF : newA
 
mkTypeConstrAppls m (KindedType t k p) =
    do newT <- mkTypeConstrAppls m t
       return $ KindedType newT k p

mkTypeConstrAppls _ (LazyType t p) =
    do newT <- mkTypeConstrAppls TopLevel t
       return $ LazyType newT p

mkTypeConstrAppls _ (ProductType ts ps) =
    do newTs <- mapM (mkTypeConstrAppls TopLevel) ts
       return $ ProductType newTs ps

mkTypeConstrAppls _ (FunType t1 a t2 ps) =
    do newT1 <- mkTypeConstrAppls TopLevel t1
       newT2 <- mkTypeConstrAppls TopLevel t2
       return $ FunType newT1 a newT2 ps

expandApplKind :: ClassMap -> Class -> Kind
expandApplKind cMap c = 
    case c of
    Intersection (a:_) _ -> 
	case anaClassId cMap a of
	    Just k -> case k of 
			     ExtClass c2 _ _ -> expandApplKind cMap c2
			     _ -> k
	    _ -> error "expandKind"
    _ -> star

inferKind :: Type -> State Env (Maybe Kind)
inferKind (TypeName i k _) = do mk <- getIdKind i
				return $ case mk of 
						 Nothing -> Just k
						 _ -> mk
inferKind (TypeAppl t1 t2) = 
    do m1 <- inferKind t1 
       case m1 of 
	    Nothing -> return Nothing
	    Just mk1 ->
		case mk1 of 
		       KindAppl k1 k2 _ -> do checkKind t2 k1
					      return $ Just k2
		       ExtClass c _ _ -> 
			   do cMap <- getClassMap 
			      case expandApplKind cMap c of
			            KindAppl k1 k2 _ -> do checkKind t2 k1
							   return $ Just k2
				    _ -> do addDiag $ wrongKind t1
					    return Nothing

inferKind (FunType t1 _ t2 _) = 
    do checkKind t1 star 
       checkKind t2 star
       return $ Just star 
inferKind (ProductType ts _) = 
    do ms <- mapM inferKind ts 
       let ns = map ( \ (Just x, y) -> (x, y)) 
		$ filter (isJust . fst) $ zip ms ts 
	   es = map (wrongKind . snd) $ 
		filter (not . eqKind star . fst) ns
       appendDiags es
       return $ Just star 
inferKind (LazyType t _) = 
    do checkKind t star
       return $ Just star 
inferKind (TypeToken t) = getIdKind (simpleIdToId t)
inferKind (KindedType t k _) =
    do checkKind t k
       return $ Just k
inferKind t@(MixfixType _) = 
    do unresolvedType t
       return Nothing
inferKind t =
    do unresolvedType t
       return Nothing

checkKind :: Type -> Kind -> State Env ()
checkKind t j = do
	m <- inferKind t 
	case m of 
	       Nothing -> return ()
	       Just k -> do cMap <- getClassMap
			    if eqKind (expandKind cMap k) $ expandKind cMap j
			       then return ()
			       else addDiag $ wrongKind t

noGroundType, wrongKind :: Type -> Diagnosis
noGroundType t = mkDiag Error "no ground type" t
wrongKind t = mkDiag Error "incompatible kind of type" t
unresolvedType :: Type -> State Env ()
unresolvedType = addDiag . mkDiag Error "unresolved type"

getIdKind :: Id -> State Env (Maybe Kind)
getIdKind i = 
    do tk <- getTypeMap
       let m = getKind tk i
       case m of
	    Nothing -> do addDiag $ mkDiag Error "undeclared type" i
                          return Nothing
	    Just k -> return $ Just k

getKind :: TypeMap -> Id -> Maybe Kind
getKind tk i = 
       case Map.lookup i tk of
       Nothing -> Nothing
       Just (TypeInfo k _ _ _) -> Just k

isTypeVar :: TypeMap -> Id -> Bool
isTypeVar tk i = 
       case Map.lookup i tk of
       Just (TypeInfo _ _ _ TypeVarDefn) -> True
       _ -> False

anaType :: Type -> State Env (Maybe Kind, Type)
anaType t = 
    do newT <- mkTypeConstrAppls TopLevel t
       k <- inferKind newT
       return (k, newT)

mkBracketToken :: BracketKind -> [Pos] -> [Token]
mkBracketToken k ps = 
    if null ps then mkBracketToken k [nullPos]
       else zipWith Token (getBrackets k) [head ps, last ps] 

getBrackets :: BracketKind -> [String]
getBrackets k = 
    case k of Parens -> ["(", ")"]
	      Squares -> ["[", "]"]
	      Braces -> ["{", "}"]

