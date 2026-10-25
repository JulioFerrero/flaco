#import "Flaco.h"

typedef struct { CGFloat r, g, b; } FLRGB;
typedef struct { CGFloat h, s, l; } FLHSL;

static FLRGB FLFromHex(uint32_t hex) {
    return (FLRGB){(hex >> 16 & 0xFF) / 255.0, (hex >> 8 & 0xFF) / 255.0, (hex & 0xFF) / 255.0};
}

static FLRGB FLFromHSL(CGFloat h, CGFloat s, CGFloat l) {
    CGFloat c = (1 - fabs(2 * l - 1)) * s, sector = h * 6;
    CGFloat x = c * (1 - fabs(fmod(sector, 2) - 1)), m = l - c / 2;
    FLRGB rgb;
    if (sector < 1) rgb = (FLRGB){c, x, 0};
    else if (sector < 2) rgb = (FLRGB){x, c, 0};
    else if (sector < 3) rgb = (FLRGB){0, c, x};
    else if (sector < 4) rgb = (FLRGB){0, x, c};
    else if (sector < 5) rgb = (FLRGB){x, 0, c};
    else rgb = (FLRGB){c, 0, x};
    return (FLRGB){rgb.r + m, rgb.g + m, rgb.b + m};
}

static FLHSL FLToHSL(FLRGB c) {
    CGFloat high = MAX(c.r, MAX(c.g, c.b)), low = MIN(c.r, MIN(c.g, c.b));
    CGFloat l = (high + low) / 2, d = high - low;
    if (d < 0.0001) return (FLHSL){0, 0, l};
    CGFloat s = MIN(1, d / (1 - fabs(2 * l - 1))), h;
    if (high == c.r) h = fmod((c.g - c.b) / d, 6);
    else if (high == c.g) h = (c.b - c.r) / d + 2;
    else h = (c.r - c.g) / d + 4;
    h /= 6;
    return (FLHSL){h < 0 ? h + 1 : h, s, l};
}

static UIColor *FLColor(FLRGB c) { return [UIColor colorWithRed:c.r green:c.g blue:c.b alpha:1]; }

static uint32_t FLHex(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return (uint32_t)lround(r * 255) << 16 | (uint32_t)lround(g * 255) << 8 | (uint32_t)lround(b * 255);
}

static UIColor *FLMixColor(UIColor *a, UIColor *b, CGFloat t) {
    CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
    [a getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [b getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * t green:g1 + (g2 - g1) * t blue:b1 + (b2 - b1) * t alpha:1];
}

@implementation FLTheme

+ (FLTheme *)neutral {
    return [[FLTheme alloc] initWithArray:@[@0x101010, @0x272727, @0x171717, @0x282828, @0xE4E4E4, @0xF2F2F2]];
}

- (instancetype)initWithArray:(NSArray<NSNumber *> *)hexes {
    if ((self = [super init])) {
        NSArray *colors = [hexes valueForKey:@"unsignedIntValue"];
        if (colors.count < 6) return FLTheme.neutral;
        _background = FLColor(FLFromHex([colors[0] unsignedIntValue]));
        _glow = FLColor(FLFromHex([colors[1] unsignedIntValue]));
        _panel = FLColor(FLFromHex([colors[2] unsignedIntValue]));
        _line = FLColor(FLFromHex([colors[3] unsignedIntValue]));
        _accent = FLColor(FLFromHex([colors[4] unsignedIntValue]));
        _text = FLColor(FLFromHex([colors[5] unsignedIntValue]));
    }
    return self;
}

- (NSArray<NSNumber *> *)array {
    return @[@(FLHex(_background)), @(FLHex(_glow)), @(FLHex(_panel)), @(FLHex(_line)), @(FLHex(_accent)), @(FLHex(_text))];
}

- (UIColor *)secondary { return [_text colorWithAlphaComponent:0.62]; }
- (UIColor *)faint { return [_text colorWithAlphaComponent:0.22]; }
- (UIColor *)tint { return [_accent colorWithAlphaComponent:0.16]; }

- (FLTheme *)mix:(FLTheme *)o amount:(CGFloat)t {
    FLTheme *m = [FLTheme new];
    m.background = FLMixColor(_background, o.background, t);
    m.glow = FLMixColor(_glow, o.glow, t);
    m.panel = FLMixColor(_panel, o.panel, t);
    m.line = FLMixColor(_line, o.line, t);
    m.accent = FLMixColor(_accent, o.accent, t);
    m.text = FLMixColor(_text, o.text, t);
    return m;
}

- (BOOL)isEqual:(id)other { return [other isKindOfClass:FLTheme.class] && [[other array] isEqualToArray:self.array]; }
- (NSUInteger)hash { return self.array.hash; }

typedef struct { FLRGB rgb; CGFloat h, s, vivid; } FLSample;

/// Reads a cover at 32 × 32. Colours fall into 24 hue bins weighted by chroma: the heaviest bin gives the
/// ground; the accent is the heaviest bin away from it, lifted until it reads on the dark ground. As in Flaco.
+ (FLTheme *)paletteFromImage:(UIImage *)image {
    enum { side = 32, count = side * side };
    uint8_t pixels[count * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!context || !image.CGImage) { if (context) CGContextRelease(context); return FLTheme.neutral; }
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(context);

    static FLSample samples[count];
    int binOf[count];
    CGFloat weights[24] = {0}, chroma = 0;
    for (int i = 0; i < count; i++) {
        FLRGB rgb = {pixels[i * 4] / 255.0, pixels[i * 4 + 1] / 255.0, pixels[i * 4 + 2] / 255.0};
        FLHSL hsl = FLToHSL(rgb);
        CGFloat vivid = hsl.s * (1 - fabs(2 * hsl.l - 1));
        int bin = MIN(23, (int)(hsl.h * 24));
        samples[i] = (FLSample){rgb, hsl.h, hsl.s, vivid};
        binOf[i] = bin;
        weights[bin] += vivid;
        chroma += vivid;
    }
    if (chroma / count <= 0.04) return FLTheme.neutral;
    int base = 0;
    for (int b = 1; b < 24; b++) if (weights[b] > weights[base]) base = b;

    CGFloat total = 0, hue = 0, saturation = 0;
    for (int i = 0; i < count; i++) {
        if (binOf[i] != base) continue;
        total += samples[i].vivid;
        hue += samples[i].h * samples[i].vivid;
        saturation += samples[i].s * samples[i].vivid;
    }
    hue /= MAX(total, 0.0001);
    saturation /= MAX(total, 0.0001);

    int accentBin = base;
    CGFloat best = -1;
    for (int b = 0; b < 24; b++) {
        int d = abs(b - base);
        CGFloat score = weights[b] * (0.35 + MIN(MIN(d, 24 - d), 6) / 6.0);
        if (score > best) { best = score; accentBin = b; }
    }
    // The most vivid fifth of the accent bin, averaged.
    NSMutableArray<NSNumber *> *members = [NSMutableArray array];
    for (int i = 0; i < count; i++) if (binOf[i] == accentBin) [members addObject:@(i)];
    [members sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        CGFloat va = samples[a.intValue].vivid, vb = samples[b.intValue].vivid;
        return va > vb ? NSOrderedAscending : va < vb ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger take = MAX(1, members.count / 5);
    FLRGB mean = {0, 0, 0};
    for (NSUInteger k = 0; k < MIN(take, members.count); k++) {
        FLRGB c = samples[members[k].intValue].rgb;
        mean.r += c.r; mean.g += c.g; mean.b += c.b;
    }
    CGFloat n = MAX(1, MIN(take, members.count));
    FLHSL accent = FLToHSL((FLRGB){mean.r / n, mean.g / n, mean.b / n});

    CGFloat s = MIN(MAX(saturation, 0.2), 0.6);
    FLTheme *theme = [FLTheme new];
    theme.background = FLColor(FLFromHSL(hue, s * 0.45, 0.065));
    theme.glow = FLColor(FLFromHSL(hue, s * 0.55, 0.16));
    theme.panel = FLColor(FLFromHSL(hue, s * 0.42, 0.095));
    theme.line = FLColor(FLFromHSL(hue, s * 0.32, 0.155));
    theme.text = FLColor(FLFromHSL(hue, 0.25, 0.93));
    theme.accent = FLColor(FLFromHSL(accent.h, MIN(MAX(accent.s, 0.45), 0.85), MIN(MAX(accent.l, 0.68), 0.78)));
    return theme;
}

@end
