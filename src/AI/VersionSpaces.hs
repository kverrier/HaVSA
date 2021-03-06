{-# LANGUAGE GADTs, TypeSynonymInstances, FunctionalDependencies, MultiParamTypeClasses  #-}
module AI.VersionSpaces where

import Control.Arrow ((***))

-- | Representation of a traditional version space, as described by
-- Hirsh: Hirsh, H.: 1991, 'Theoretical Underpinnings of Version
-- Spaces'. In: Proceedings of the Twelfth International Joint
-- Conference on Artificial Intelligence. pp.  665–670.
data BSR a i o = EmptyBSR
               | BSR { storage :: a
                     , narrow :: BSR a i o -> i -> o -> BSR a i o
                     , hypos  :: BSR a i o -> [i -> o]
                     }

-- | Renders a BSR to a string to show whether the BSR is empty or
-- not.  Additional details place undesirable restrictions on the
-- state storage.
showBSR :: BSR a i o -> String
showBSR EmptyBSR    = "Empty"
showBSR (BSR _ _ _) = "non-empty"

-- | Union two versionspaces, generating a third.
union :: VersionSpace a b -> VersionSpace a b -> VersionSpace a b
union Empty y = y
union x Empty = x
union x y     = Union x y

-- | Join two versionspaces, generating a third.
join :: (Eq b, Eq d) => VersionSpace a b -> VersionSpace c d -> VersionSpace (a, c) (b, d)
join Empty _ = Empty
join _ Empty = Empty
join x y     = Join x y

-- | Transform a version space to mutate the input and/or output types.
-- Transforms require that three functions be specified:
--
--  [@i -> a@] Transform the input of the resulting version space to the input of the initial versionspace.
--
--  [@o -> b@] Transform the output of the initial versionspace into the output of the resulting versionspace.
--
--  [@b -> o@] Transform the output of the /resulting/ versionspace
--  into the output of the /initial/ versionspace.  This is necessary
--  to support training: the training examples will be in terms of the
--  resulting versionspace, so the output must be transformed back
--  into the terms of the initial versionspace.
tr :: (Eq b) => (i -> a) -> (o -> b) -> (b -> o) -> VersionSpace a b -> VersionSpace i o
tr _   _    _    Empty = Empty
tr tin tout fout vs    = Tr tin tout fout vs

-- | Version Space algebraic operators:
data VersionSpace i o where
  -- The empty, or collapsed versionspace.
  Empty :: VersionSpace i o
  -- A basic leaf versionspace, this just wraps a 'BSR'
  VS :: BSR a i o -> VersionSpace i o
  -- The Join of two versionspaces.  This should not be used directly, rather, use the 'join' function.
  Join :: (Eq d, Eq b) => VersionSpace a b -> VersionSpace c d -> VersionSpace (a, c) (b, d)
  -- The union of two versionspaces.  This should not be used directly, rather, use the 'union' function.
  Union :: VersionSpace a b -> VersionSpace a b -> VersionSpace a b
  -- The transform of two versionspaces.  This should not be used directly, rather, use the 'tr' function.
  Tr :: (Eq b) => (i -> a) -> (o -> b) -> (b -> o) -> VersionSpace a b -> VersionSpace i o

-- | Serializes a versionspace to a human-readable string, for certain values of 'human'.
showVS :: VersionSpace i o -> String
showVS Empty           = "Empty"
showVS (VS hs)         = showBSR hs
showVS (Union vs1 vs2) = "["++showVS vs1++" U "++showVS vs2++"]"
showVS (Join vs1 vs2)  = "["++showVS vs1++" |><| "++showVS vs2++"]"
showVS (Tr _ _ _ vs)   = "[TR "++showVS vs++"]"

-- | Train a version space, reducing the set of valid hypotheses.  We
-- handle the Empty VS cases prior to the corresponding non-empty
-- cases because the Empties are simplifying cases, so logic can be
-- short-circuited by collapsing parts of the hierarchy before
-- recursing.
train :: (Eq o) => VersionSpace i o -> i -> o -> VersionSpace i o
train Empty  _ _ = Empty
train (VS b) i o = case (narrow b) b i o of
  EmptyBSR -> Empty
  bsr      -> VS bsr

-- | The join of an empty VS with any other VS is empty.
train (Join Empty _)    _       _       = Empty
train (Join _ Empty)    _       _       = Empty
train (Join vs1 vs2)   (i1,i2) (o1, o2) = join (train vs1 i1 o1) (train vs2 i2 o2)

-- | Unioning a VS with an empty VS is just the non-empty VS.
train (Union vs1 Empty) _       _       = vs1
train (Union Empty vs2) _       _       = vs2
train (Union vs1 vs2)   i       o       = union (train vs1 i o) (train vs2 i o)

-- | Any transform on an empty VS is just an empty VS.
train (Tr _ _ _ Empty)           _ _  = Empty
train (Tr tin tout fout innerVS) i o  = tr tin tout fout trainedVS
    where trainedVS = train innerVS (tin i) (tout o)

-- | Retrieve the valid hypotheses for a version space.
hypotheses :: VersionSpace i o -> [(i -> o)] -- could be i -> [o]
hypotheses Empty              = []
hypotheses (VS hs)            = (hypos hs) hs
hypotheses (Join vs1 vs2)     = zipWith (***) (hypotheses vs1) (hypotheses vs2)
hypotheses (Union vs1 vs2)    = hypotheses vs1 ++ hypotheses vs2
hypotheses (Tr fin _ fout vs) = map (\x->fout . x . fin) $ hypotheses vs

-- | Runs all valid hypotheses from the version space
-- on the specified input.
runVS :: VersionSpace a b -> a -> [b]
runVS vs input = map (\x->x $ input) $ hypotheses vs

{-

Notes regarding error-tolerance:

  * The Similar function happens at the narrowing stage - I think this
can be done in the narrow fun. on BSR.  However, this assumes that
user error on different aspects of the input is independent of the
other aspects of error in the same way that the components of the
trained hypotheses are independent.

  * The Aggregate function operates on sets of hypotheses.  It
converts a set of hypotheses into a new, potentially smaller, set of
hypotheses.  It could probably do better if it could use the
demonstrations to determine the best aggregation.  I don't think
Aggregation can happen solely at the leaves (although it may be
worthwhile to aggregate at that level).  Rather, I think it may be
necessary to aggregate on higher-evel types.

   This might not be a problem though, since the only reasons I can
think of to aggregate at a higher level are due to dependencies
between sibling version spaces.

-}