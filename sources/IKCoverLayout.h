#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <math.h>

typedef struct { CGRect first, second; BOOL fits; } IKCoverTextLayout;

// 一行里放得下的文字从哪里开始画。alignment：0 靠左、1 居中、2 靠右、3 自定义。
// anchor 是“文字中心想放在哪里”，用这一行自己的坐标：岛把胶囊的中线（自定义时再加上偏移）换算过来，
// 所以居中是相对整个胶囊、也就是屏幕中线，而不是相对封面右边剩下的那块文字区域。
// 中心对不准时（左边有封面挡着、右边到了胶囊边缘）就停在这一行的边上，文字不会被挡住。
// anchor 为 NAN（没有胶囊信息）时，居中退回到按这一行自己的宽度居中
static inline CGFloat IKTextOrigin(CGFloat width, CGFloat textWidth, NSInteger alignment, CGFloat anchor) {
    CGFloat spare = MAX(0, width - textWidth);
    if (alignment == 2) return spare;
    if (alignment != 1 && alignment != 3) return 0;
    if (isnan(anchor)) return spare / 2;
    return MAX(0, MIN(spare, anchor - textWidth / 2));
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
