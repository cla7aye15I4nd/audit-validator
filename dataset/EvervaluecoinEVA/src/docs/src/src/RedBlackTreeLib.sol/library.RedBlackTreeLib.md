# RedBlackTreeLib
[Git Source](https://github.com/artechsoft/orderbook/blob/bbd55f017f77567506e5700d9133d68be9d96234/src/RedBlackTreeLib.sol)

*This contract implements a red-black tree, which is a self-balancing binary search tree.
It is designed to be used for managing order books or any other sorted data structures efficiently.*


## State Variables
### EMPTY
Represents an empty value in the tree; it is used to denote nodes that do not exist or are empty.


```solidity
uint256 private constant EMPTY = 0;
```


## Functions
### exists

*Checks if a node with a given value exists in the Red-Black tree.
This function determines whether a node with the specified value is present
in the tree by checking the following:
1. If the provided `value` is `EMPTY` (commonly `0`), it returns `false`
indicating the node cannot exist.
2. If the `value` matches the root of the tree, it returns `true` as the root
node is always considered to exist.
3. Otherwise, it checks if the node has a parent that is not `EMPTY`. If the
node has a valid parent, it implies the node is present in the tree.
To optimize gas usage, the function stores the node reference in a local
variable to avoid repeated storage access.*


```solidity
function exists(Tree storage self, uint256 value) internal view returns (bool _exists);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node to check for existence.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_exists`|`bool`|A boolean indicating whether the node with the specified value exists in the tree.|


### getNode

*Retrieves various attributes of a node in the Red-Black tree.
This function is used to access the key properties of a node identified by its `value`
in the Red-Black tree. It ensures that the node exists before accessing its properties.
Steps performed:
1. Validates that the node with the specified `value` exists in the tree using `require`.
If the node does not exist, the function reverts with an error.
2. Accesses the node's properties including its parent, left and right children,
whether it's red, the number of keys, and a custom count.
3. Returns the following attributes of the node:
- `_parent`: The value of the parent node.
- `_left`: The value of the left child node.
- `_right`: The value of the right child node.
- `_red`: A boolean indicating whether the node is red.
- `countTotalOrders`: The number orders in node.
- `countValueOrders`: The sum of value in total orders.*


```solidity
function getNode(Tree storage self, uint256 value) internal view returns (Node storage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage containing all nodes and the root.|
|`value`|`uint256`|The value of the node whose attributes are to be retrieved.|


### first

*Retrieves the value of the leftmost node in the Red-Black tree.
This function returns the smallest value in the tree, which is the
leftmost node when traversing from the root. It starts from the root node
and continually moves to the left child until it reaches a node with no
left child. The function performs the following steps:
1. Initializes `_value` with the root of the tree.
2. Checks if the tree is empty (i.e., the root is `EMPTY`). If so, returns `0`.
3. If the tree is not empty, it enters a loop to find the leftmost node:
- Updates `_value` to the left child of the current node.
- Updates the `currentNode` to the newly found left child node.
4. Continues this process until a node with no left child is reached.
5. Returns the value of the leftmost node found.*


```solidity
function first(Tree storage self) internal view returns (uint256 _value);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage. This struct contains the nodes and root of the Red-Black tree.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_value`|`uint256`|The value of the leftmost node in the tree. If the tree is empty, it returns `0`.|


### last

*Retrieves the value of the rightmost node in the Red-Black tree.
This function returns the largest value in the tree, which is the
rightmost node when traversing from the root. It starts from the root node
and continually moves to the right child until it reaches a node with no
right child. The function performs the following steps:
1. Initializes `_value` with the root of the tree.
2. Checks if the tree is empty (i.e., the root is `EMPTY`). If so, returns `0`.
3. If the tree is not empty, it enters a loop to find the rightmost node:
- Updates `_value` to the right child of the current node.
- Continues this process until a node with no right child is reached.
4. Returns the value of the rightmost node found.*


```solidity
function last(Tree storage self) internal view returns (uint256 _value);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage. This struct contains the nodes and root of the Red-Black tree.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_value`|`uint256`|The value of the rightmost node in the tree. If the tree is empty, it returns `0`.|


### next

*Finds the successor of a given node in the Red-Black tree.
The successor of a node is the node with the smallest value that is greater than
the given node's value. The function performs the following steps:
1. Ensures the provided `value` is not `EMPTY`. If it is, the function reverts with
an error message.
2. Checks if the given node has a right child. If it does, the successor is the
minimum value in the right subtree.
3. If the node has no right child, it searches among the ancestors of the node.
- Moves up to the parent node until it finds a node that is a left child of its
parent or reaches the root.*


```solidity
function next(Tree storage self, uint256 value) internal view returns (uint256 _cursor);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node for which the successor is to be found.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_cursor`|`uint256`|The value of the successor node. If there is no successor, it returns `EMPTY`.|


### prev

*Finds the predecessor of a given node in the Red-Black tree.
The predecessor of a node is the node with the largest value that is smaller than
the given node's value. The function performs the following steps:
1. Ensures the provided `value` is not `EMPTY`. If it is, the function reverts with
an error message.
2. Checks if the given node has a left child. If it does, the predecessor is the
maximum value in the left subtree.
3. If the node has no left child, it searches among the ancestors of the node.
- Moves up to the parent node until it finds a node that is a right child of its
parent or reaches the root.*


```solidity
function prev(Tree storage self, uint256 value) internal view returns (uint256 _cursor);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node for which the predecessor is to be found.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_cursor`|`uint256`|The value of the predecessor node. If there is no predecessor, it returns `EMPTY`.|


### insert

*Inserts a new node with the given value and key into the Red-Black tree.
This function adds a node to the tree, maintaining the Red-Black properties. The process follows these steps:
1. Verifies that the `value` is not `EMPTY`. If it is, the function reverts.
2. Checks that the key-value pair does not already exist in the tree. If it does, the function reverts.
3. Starts from the root and traverses the tree to find the appropriate insertion point.
- Updates the `cursor` as it moves through the tree.
- Increments the count of nodes in the subtrees to maintain correct statistics.
4. Once the correct position is found, a new node is created, and its parent, left, and right pointers are set.
- The node is colored red by default.
5. The function then fixes up the tree to maintain the Red-Black properties.*


```solidity
function insert(Tree storage self, uint256 value) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage that contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node to be inserted into the tree.|


### remove

*Removes a key from a node in the Red-Black tree.
This function performs the following steps:
1. Ensures that the value to delete is not `EMPTY` and that the key exists in the node.
2. Removes the key from the node's keys array.
3. If the node has no keys left, it finds a replacement node and updates the tree:
- If the node has at most one child, it directly replaces the node.
- If the node has two children, it finds the successor (smallest node in the right subtree) to replace it.
4. Adjusts the tree structure to maintain Red-Black properties.
5. Deletes the old node and updates the tree structure accordingly.*


```solidity
function remove(Tree storage self, uint256 value) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value identifying the node where the key is to be removed.|


### treeMinimum

*Finds the minimum value node in the Red-Black tree starting from a given node.
This function traverses the tree starting from the node identified by `value`,
and continually moves to the left child until it reaches the leftmost node.
The leftmost node is the one with the smallest value in the subtree.
The function performs the following steps:
1. Initializes `value` as the starting node.
2. Enters a loop that continues as long as the current node has a left child.
- Updates `value` to the left child of the current node.
3. When a node with no left child is found, the function returns the value
of that node, as it is the minimum in the subtree.*


```solidity
function treeMinimum(Tree storage self, uint256 value) private view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The starting node from which to search for the minimum value.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The value of the minimum node in the subtree. If the subtree is empty, it returns `EMPTY`.|


### treeMaximum

*Finds the maximum value node in the Red-Black tree starting from a given node.
This function traverses the tree starting from the node identified by `value`,
and continually moves to the right child until it reaches the rightmost node.
The rightmost node is the one with the largest value in the subtree.
The function performs the following steps:
1. Initializes `value` as the starting node.
2. Enters a loop that continues as long as the current node has a right child.
- Updates `value` to the right child of the current node.
3. When a node with no right child is found, the function returns the value
of that node, as it is the maximum in the subtree.*


```solidity
function treeMaximum(Tree storage self, uint256 value) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, which contains the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The starting node from which to search for the maximum value.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The value of the maximum node in the subtree. If the subtree is empty, it returns `EMPTY`.|


### rotateLeft

*Performs a left rotation on a node in the Red-Black tree.
A left rotation is a fundamental operation in balancing a Red-Black tree.
It repositions the nodes to ensure the tree remains balanced after insertion
or deletion operations. The function does the following:
1. Identifies the right child (`cursor`) of the node (`value`) to be rotated.
2. Updates the right child of `value` to the left child of `cursor`.
3. Updates the parent of the left child of `cursor` (if it exists) to be `value`.
4. Repositions `cursor` as the parent of `value` and updates the relevant pointers.
5. If `value` was the root, `cursor` becomes the new root.
6. Recalculates the `count` property for `value` and `cursor` to maintain accurate
node counts, optimizing the process by reducing redundant calculations.*


```solidity
function rotateLeft(Tree storage self, uint256 value) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, containing the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node that needs to be rotated to the left.|


### rotateRight

*Performs a right rotation on the node identified by `value` within a Red-Black tree.
A right rotation in a Red-Black tree is used to maintain the tree's balanced structure.
In a right rotation:
- The left child of the node (`cursor`) becomes the new root of the subtree.
- The original node (`value`) moves down to become the right child of `cursor`.
The function updates the relevant parent and child pointers to maintain the correct tree structure.
The function follows these steps:
1. Assigns the left child of `value` to `cursor`, and stores the node in `nodeCursor`.
2. Moves the right child of `cursor` to become the left child of `value`.
3. Updates the parent of `cursor` to be the parent of `value`, and adjusts the parent's child pointer.
4. Sets `value` as the right child of `cursor`, completing the rotation.
5. Updates the `count` properties of both `cursor` and `value` to reflect the new subtree sizes.*


```solidity
function rotateRight(Tree storage self, uint256 value) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, containing the nodes and root of the Red-Black tree.|
|`value`|`uint256`|The value of the node to rotate right.|


### insertFixup

*Corrects the properties of the Red-Black Tree after an insertion.
This function ensures the tree adheres to Red-Black properties:
1. No two consecutive red nodes.
2. Every path from a node to its descendant leaves has the same number of black nodes.
3. The root is always black.
The function operates as follows:
1. It checks if the newly inserted node's parent is red and if the node is not the root.
2. If the parent is a left child of its parent (grandparent), it handles two cases:
- Case 1: The grandparent's right child (uncle) is red. It recolors the parent, uncle, and grandparent, and then moves up to the grandparent.
- Case 2: The uncle is black. If the newly inserted node is a right child, it performs a left rotation on the parent node. Then, it recolors and performs a right rotation on the grandparent.
3. If the parent is a right child of the grandparent, it similarly handles two cases:
- Case 1: The grandparent's left child (uncle) is red. It recolors the parent, uncle, and grandparent, and then moves up to the grandparent.
- Case 2: The uncle is black. If the newly inserted node is a left child, it performs a right rotation on the parent node. Then, it recolors and performs a left rotation on the grandparent.
4. Finally, it ensures the root of the tree is black.*


```solidity
function insertFixup(Tree storage self, uint256 value) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, representing the Red-Black tree.|
|`value`|`uint256`|The value of the node that was recently inserted and may need fixing.|


### replaceParent

*Replaces the parent reference of a node `b` with node `a`.
This function updates the parent reference of node `a` to match the parent of node `b`,
and adjusts the parent's link to point to node `a` instead of node `b`.
- If node `b` is the root of the tree, node `a` becomes the new root.
- Otherwise, node `a` replaces node `b` as a child of node `b`'s parent.*


```solidity
function replaceParent(Tree storage self, uint256 a, uint256 b) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|A reference to the `Tree` struct in storage, representing the tree.|
|`a`|`uint256`|The node that will replace node `b`.|
|`b`|`uint256`|The node that will be replaced by node `a`.|


### removeFixup

*Restores Red-Black tree properties after the removal of a node.
This function ensures that the Red-Black tree maintains its properties after
removing a node. It corrects the tree by performing color adjustments and rotations.
The function:
1. Iterates up the tree from the node that was removed, adjusting colors and performing rotations
as necessary to maintain Red-Black tree properties.
2. Ensures that the root of the tree remains black and all properties of Red-Black trees are preserved.*


```solidity
function removeFixup(Tree storage self, uint256 value) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`self`|`Tree`|The `Tree` storage reference containing the tree nodes and root.|
|`value`|`uint256`|The value of the node that needs correction after removal.|


## Errors
### RBT__StartingValueCannotBeZero

```solidity
error RBT__StartingValueCannotBeZero();
```

### RBT__ValuesDoesNotExist

```solidity
error RBT__ValuesDoesNotExist();
```

### RBT__NodeDoesNotExist

```solidity
error RBT__NodeDoesNotExist();
```

### RBT__ValueToInsertCannotBeZero

```solidity
error RBT__ValueToInsertCannotBeZero();
```

### RBT__ValueCannotBeZero

```solidity
error RBT__ValueCannotBeZero();
```

## Structs
### Node
Struct representing a node in the Red-Black Tree.


```solidity
struct Node {
    uint256 parent;
    uint256 left;
    uint256 right;
    bool red;
}
```

### Tree
Struct representing the entire Red-Black Tree


```solidity
struct Tree {
    uint256 root;
    mapping(uint256 => Node) nodes;
}
```

