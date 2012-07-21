{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rename (rename) where

import Ast
import Control.Arrow (first)
import Control.Monad (ap, liftM, foldM, mapM, Monad)
import Control.Monad.State (evalState, State, get, put)
import Data.Char (isLower)
import Guid

rename :: Expr -> Expr
rename = run . rename' id

rename' :: (String -> String) -> Expr -> GuidCounter Expr
rename' env expr =
    case expr of

      Range e1 e2 -> Range `liftM` rnm e1
                              `ap` rnm e2
      
      Access e x -> Access `liftM` rnm e
                              `ap` return x

      Binop op@(h:_) e1 e2 ->
        let rop = if isLower h || '_' == h
                  then env op
                  else op
        in Binop rop `liftM` rnm e1
                        `ap` rnm e2

      Lambda x e -> do
          (rx, env') <- extend env x
          Lambda rx `liftM` rename' env' e

      App e1 e2 -> App `liftM` rnm e1
                          `ap` rnm e2

      If e1 e2 e3 -> If `liftM` rnm e1
                           `ap` rnm e2
                           `ap` rnm e3

      Lift e es -> Lift `liftM` rnm e
                           `ap` mapM rnm es

      Fold e1 e2 e3 -> Fold `liftM` rnm e1
                               `ap` rnm e2
                               `ap` rnm e3

      Async e -> Async `liftM` rnm e

      Let defs e ->
          let (fs,argss,es) = unzip3 $ map (\(Definition a b c) -> (a,b,c)) defs in
          do env' <- foldM (\acc x -> snd `liftM` extend acc x) env fs
             es' <- mapM (rename' env') es; re <- rename' env' e
             return $ Let (zipWith3 Definition (map env' fs) argss es') re

      Var x -> return . Var $ env x

      Data name es -> Data name `liftM` mapM rnm es

      Case e cases -> Case `liftM` rnm e
                              `ap` mapM (patternRename env) cases

      _ -> return expr

  where rnm = rename' env

extend :: (String -> String) -> String -> GuidCounter (String, String -> String)
extend env x = do
  n <- guid
  let rx = map (\c -> if c == '\'' then '_' else c) $ x ++ "_" ++ show n
  return (rx, \y -> if y == x then rx else env y)

patternExtend :: Pattern -> (String -> String) -> GuidCounter (Pattern, String -> String)
patternExtend pattern env =
    case pattern of
      PAnything -> return (PAnything, env)
      PVar x -> first PVar `liftM` extend env x
      PData name ps ->
          first (PData name . reverse) `liftM` foldM f ([], env) ps
                 where f (rps,env') p = do (rp,env'') <- patternExtend p env'
                                           return (rp:rps, env'')

patternRename :: (String -> String) -> (Pattern, Expr) -> GuidCounter (Pattern, Expr)
patternRename env (p,e) = do
  (rp,env') <- patternExtend p env
  re <- rename' env' e
  return (rp,re)
