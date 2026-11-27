#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef struct { CGRect first, second; BOOL fits; } IKCoverTextLayout;

// Align the stationary text inside the part of the row available to both labels.
static inline CGFloat IKTextOrigin(CGFloat width, CGFloat textWidth, NSInteger alignment) {
    CGFloat spare = MAX(0, width - textWidth);
    return alignment == 2 ? spare : (alignment == 1 ? spare / 2 : 0);
}

static inline CGRect IKCoverDisc(CGSize shell, CGFloat cutout, CGFloat band) {
    CGFloat shoulder = MAX(0, (shell.width - cutout) / 2);
    CGFloat diameter = MAX(0, MIN(56, MIN(shell.height - band - 2, shoulder - 18)));
    return CGRectMake(12, (shell.height - diameter) / 2, diameter, diameter);
}

static inline IKCoverTextLayout IKCoverRows(CGSize shell, CGFloat band, CGFloat leading, BOOL two) {
    CGFloat width = MAX(0, shell.width - leading - 18);
    CGRect first = CGRectMake(leading, band + 6, width, 22);
    CGRect second = CGRectMake(leading, CGRectGetMaxY(first), width, 18);
    // The bottom of the row must clear the rounded shoulder, including right-aligned glyphs.
    BOOL fits = width >= 18 && CGRectGetMaxY(two ? second : first) + 5 <= shell.height;
    return (IKCoverTextLayout){first, second, fits};
}
