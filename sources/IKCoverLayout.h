#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef struct { CGRect first, second; BOOL fits; } IKCoverTextLayout;

static inline IKCoverTextLayout IKCoverRows(CGSize shell, CGFloat band, CGFloat leading, BOOL two) {
    CGFloat width = MAX(0, shell.width - leading - 18);
    CGRect first = CGRectMake(leading, band + 6, width, 22);
    CGRect second = CGRectMake(leading, CGRectGetMaxY(first), width, 18);
    BOOL fits = width >= 18 && CGRectGetMaxY(two ? second : first) <= shell.height;
    return (IKCoverTextLayout){first, second, fits};
}
