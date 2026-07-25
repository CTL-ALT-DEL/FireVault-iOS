//
//  FireVaultBreadcrumbEnergySaver.m
//  FireVault
//
//  Reduces Breadcrumbs GPS power use while preserving stop and route sampling.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <float.h>
#import <objc/runtime.h>

static const NSTimeInterval FVWaypointInterval = 120.0;
static const CLLocationDistance FVDeferredDistance = 250.0;
static const void *FVLastWaypointTimestampKey = &FVLastWaypointTimestampKey;
static const void *FVManagerConfiguredKey = &FVManagerConfiguredKey;

typedef void (*FVLocationUpdateIMP)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *);
static FVLocationUpdateIMP FVOriginalLocationUpdate = NULL;

static void FVConfigureLowPowerManager(CLLocationManager *manager) {
    if ([objc_getAssociatedObject(manager, FVManagerConfiguredKey) boolValue]) {
        return;
    }

    manager.activityType = CLActivityTypeAutomotiveNavigation;
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    manager.distanceFilter = 75.0;
    manager.pausesLocationUpdatesAutomatically = YES;

    if ([manager respondsToSelector:@selector(allowDeferredLocationUpdatesUntilTraveled:timeout:)]) {
        [manager allowDeferredLocationUpdatesUntilTraveled:FVDeferredDistance
                                                    timeout:FVWaypointInterval];
    }

    objc_setAssociatedObject(
        manager,
        FVManagerConfiguredKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

static void FVSmartLocationUpdate(
    id store,
    SEL selector,
    CLLocationManager *manager,
    NSArray<CLLocation *> *locations
) {
    FVConfigureLowPowerManager(manager);

    CLLocation *latest = locations.lastObject;
    if (latest == nil || FVOriginalLocationUpdate == NULL) {
        return;
    }

    NSDate *lastAccepted = objc_getAssociatedObject(store, FVLastWaypointTimestampKey);
    NSTimeInterval elapsed = lastAccepted == nil
        ? DBL_MAX
        : [latest.timestamp timeIntervalSinceDate:lastAccepted];

    if (elapsed < FVWaypointInterval) {
        return;
    }

    objc_setAssociatedObject(
        store,
        FVLastWaypointTimestampKey,
        latest.timestamp,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    FVOriginalLocationUpdate(store, selector, manager, @[latest]);

    if ([manager respondsToSelector:@selector(allowDeferredLocationUpdatesUntilTraveled:timeout:)]) {
        [manager allowDeferredLocationUpdatesUntilTraveled:FVDeferredDistance
                                                    timeout:FVWaypointInterval];
    }
}

__attribute__((constructor))
static void FVInstallBreadcrumbEnergySaver(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class storeClass = NSClassFromString(@"FireVault.FireVaultBreadcrumbStore");
        SEL selector = @selector(locationManager:didUpdateLocations:);
        Method method = class_getInstanceMethod(storeClass, selector);
        if (storeClass == Nil || method == NULL) {
            return;
        }

        FVOriginalLocationUpdate = (FVLocationUpdateIMP)method_getImplementation(method);
        method_setImplementation(method, (IMP)FVSmartLocationUpdate);
    });
}
