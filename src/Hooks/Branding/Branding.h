#import "../HookHelpers.h"

static __thread BOOL handlingTerminologyLocalization = NO;

NSDictionary<NSString*, NSString*>* RenameKeyOverrides(void);
NSString* PillLabelText(void);
NSString* RestoreTwitterTerminology(NSString* input);
NSAttributedString* RestoreTwitterAttributed(NSAttributedString* input);
