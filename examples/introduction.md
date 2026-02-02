# Introduction to xeus-lean

This document shows example usage of the xeus-lean Jupyter kernel.

## Basic Definitions

```lean
-- Define a simple function
def double (n : Nat) : Nat := n + n

-- Check its type
#check double

-- Evaluate it
#eval double 21
```

## Working with Lists

```lean
-- Define a list
def myList : List Nat := [1, 2, 3, 4, 5]

-- Map over it
#eval myList.map double
```

## Theorems and Proofs

```lean
-- A simple theorem
theorem add_comm (a b : Nat) : a + b = b + a := by
  sorry  -- This will show the proof goal

-- A complete proof
theorem add_zero (n : Nat) : n + 0 = n := by
  rfl
```

## Type Classes

```lean
-- Define a simple structure
structure Point where
  x : Nat
  y : Nat

-- Create an instance
def origin : Point := ⟨0, 0⟩

#check origin
```

## Inductive Types

```lean
-- Define a binary tree
inductive BinTree (α : Type) where
  | leaf : BinTree α
  | node : α → BinTree α → BinTree α → BinTree α

-- Define a simple tree
def myTree : BinTree Nat :=
  BinTree.node 5
    (BinTree.node 3 BinTree.leaf BinTree.leaf)
    (BinTree.node 7 BinTree.leaf BinTree.leaf)

#check myTree
```

## Interactive Proof Development

```lean
theorem example_proof : ∀ n : Nat, n + 0 = n := by
  intro n
  -- At this point, you can see the goal: n : Nat ⊢ n + 0 = n
  rfl
```

## Imports (when Mathlib is available)

```lean
-- import Mathlib.Data.Nat.Basic
-- import Mathlib.Tactic

-- Then you can use Mathlib theorems and tactics
```

## Tips

1. **Environment Persistence**: Each cell builds on previous cells
2. **Tab Completion**: Press Tab to see available identifiers
3. **Inspection**: Shift+Tab on an identifier to see its type
4. **Proof Goals**: Use `sorry` to see intermediate proof states
5. **Errors**: Lean will show helpful error messages with positions
