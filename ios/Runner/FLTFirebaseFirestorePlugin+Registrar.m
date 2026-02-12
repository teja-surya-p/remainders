#import <Flutter/Flutter.h>
#import <cloud_firestore/FLTFirebaseFirestorePlugin.h>
#import <cloud_firestore/FirestoreMessages.g.h>
#import <firebase_core/FLTFirebasePluginRegistry.h>

@implementation FLTFirebaseFirestorePlugin (Registrar)

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FLTFirebaseFirestorePlugin *instance = [[FLTFirebaseFirestorePlugin alloc] init];
  FirebaseFirestoreHostApiSetup([registrar messenger], instance);
  [[FLTFirebasePluginRegistry sharedInstance] registerFirebasePlugin:instance];
}

@end
