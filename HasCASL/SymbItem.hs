{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  experimental
Portability :  portable

   
   HasCASL parsable symbol items for structured specs 
-}

module HasCASL.SymbItem where

import Common.Id
import Common.Keywords
import Common.Lexer
import Common.AnnoState
import Common.Lib.Parsec

import HasCASL.HToken
import HasCASL.ParseTerm
import HasCASL.As

-- * parsers for symbols
-- | parse a (typed) symbol 
symb :: AParser Symb
symb = do i <- uninstOpId
	  do c <- colT 
	     t <- typeScheme
	     return (Symb i (Just $ SymbType t) [tokPos c])
	    <|> 
            do c <- qColonT 
	       t <- parseType 
	       return (Symb i (Just $ SymbType $ simpleTypeScheme $ 
				  LazyType t [tokPos c]) [tokPos c])
             <|> return (Symb i Nothing [])
	       
-- | parse a mapped symbol
symbMap :: AParser SymbOrMap
symbMap =   do s <- symb
	       do   f <- asKey mapsTo
		    t <- symb
		    return (SymbOrMap s (Just t) [tokPos f])
		  <|> return (SymbOrMap s Nothing [])

-- | parse kind of symbols
symbKind :: AParser (SymbKind, Token)
symbKind = try(
        do q <- pluralKeyword opS 
	   return (SK_op, q)
        <|>
        do q <- pluralKeyword functS 
	   return (SK_fun, q)
        <|>
        do q <- pluralKeyword predS 
	   return (SK_pred, q)
        <|>
        do q <- pluralKeyword typeS 
	   return (SK_type, q)
        <|>
        do q <- pluralKeyword sortS 
	   return (SK_sort, q)
        <|>
        do q <- asKey (classS ++ "es") <|> asKey classS
	   return (SK_class, q))
	<?> "kind"

-- | parse symbol items
symbItems :: AParser SymbItems
symbItems = do s <- symb
	       return (SymbItems Implicit [s] [] [])
	    <|> 
	    do (k, p) <- symbKind
               (is, ps) <- symbs
	       return (SymbItems k is [] (map tokPos (p:ps)))

symbs :: AParser ([Symb], [Token])
symbs = do s <- symb 
	   do   c <- anComma `followedWith` symb
	        (is, ps) <- symbs
		return (s:is, c:ps)
	     <|> return ([s], [])

-- | parse symbol mappings
symbMapItems :: AParser SymbMapItems
symbMapItems = 
            do s <- symbMap
	       return (SymbMapItems Implicit [s] [] [])
	    <|> 
	    do (k, p) <- symbKind
               (is, ps) <- symbMaps
	       return (SymbMapItems k is [] (map tokPos (p:ps)))

symbMaps :: AParser ([SymbOrMap], [Token])
symbMaps = 
        do s <- symbMap 
	   do   c <- anComma `followedWith` symb
	        (is, ps) <- symbMaps
		return (s:is, c:ps)
	     <|> return ([s], [])


