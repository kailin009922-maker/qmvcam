//
//  vcam_ui.m — SpringBoard 侧悬浮球 / 摇杆 / 设置面板
//
//  对应原包：VCamFloatingBall / VCamJoystickControl / VCamSettingsViewController
//  三页：设置（摇杆·滑杆）/ 多图（图片·视频槽位）/ 打光（Metal 人脸补光）
//
#import "vcam_common.h"
#import "substrate.h"
#import <PhotosUI/PhotosUI.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - 摇杆

typedef void (^QMJoystickBlock)(CGFloat nx, CGFloat ny);

@interface QMJoystick : UIView
@property (nonatomic, copy) QMJoystickBlock onChange;
@property (nonatomic, assign) CGFloat nx, ny;
@end

@implementation QMJoystick {
    CGPoint _knob;
    UIPanGestureRecognizer *_pan;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panned:)];
        [self addGestureRecognizer:_pan];
    }
    return self;
}
- (void)_panned:(UIPanGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    CGPoint c = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) * 0.42;
    CGFloat dx = p.x - c.x, dy = p.y - c.y;
    CGFloat len = sqrt(dx * dx + dy * dy);
    if (len > r) { dx *= r / len; dy *= r / len; }
    _knob = CGPointMake(c.x + dx, c.y + dy);
    self.nx = dx / r;
    self.ny = dy / r;
    if (self.onChange) self.onChange(self.nx, self.ny);
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGPoint c = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat r = MIN(rect.size.width, rect.size.height) * 0.42;
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:0.18].CGColor);
    CGContextSetLineWidth(ctx, 1);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2, r * 2));
    CGPoint k = (_knob.x == 0 && _knob.y == 0) ? c : _knob;
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:0.85].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(k.x - 13, k.y - 13, 26, 26));
}
@end

#pragma mark - 悬浮球

typedef void (^QMTapBlock)(void);

@interface QMFloatingBall : UIView
@property (nonatomic, copy) QMTapBlock onTap;
@property (nonatomic, copy) QMTapBlock onLongPress;
@end

@implementation QMFloatingBall {
    UIPanGestureRecognizer *_pan;
    CGPoint _startCenter;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.55];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panned:)];
        [self addGestureRecognizer:_pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap)];
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_lp)];
        lp.minimumPressDuration = 0.55;
        [self addGestureRecognizer:lp];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGPoint c = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokeEllipseInRect(ctx, CGRectInset(rect, 9, 9));
    CGContextMoveToPoint(ctx, c.x, c.y - 7);
    CGContextAddLineToPoint(ctx, c.x + 6, c.y + 2);
    CGContextAddLineToPoint(ctx, c.x - 6, c.y + 2);
    CGContextClosePath(ctx);
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillPath(ctx);
}
- (void)_panned:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) _startCenter = self.center;
    self.center = CGPointMake(_startCenter.x + t.x, _startCenter.y + t.y);
    if (g.state == UIGestureRecognizerStateEnded) {
        // 边缘吸附
        CGRect b = self.superview.bounds;
        CGFloat margin = 12;
        CGFloat x = MIN(MAX(self.center.x, margin + self.bounds.size.width / 2),
                        CGRectGetMaxX(b) - margin - self.bounds.size.width / 2);
        CGFloat y = MIN(MAX(self.center.y, margin + self.bounds.size.height / 2),
                        CGRectGetMaxY(b) - margin - self.bounds.size.height / 2);
        [UIView animateWithDuration:0.18 animations:^{ self.center = CGPointMake(x, y); }];
    }
}
- (void)_tap { if (self.onTap) self.onTap(); }
- (void)_lp { if (self.onLongPress) self.onLongPress(); }
@end

#pragma mark - 工具

static UIFont *QMFont(CGFloat size, BOOL bold) {
    return bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

static UIButton *QMButton(NSString *title, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = QMFont(13, YES);
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    b.layer.cornerRadius = 8;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:34].active = YES;
    return b;
}

static UISlider *QMSlider(id target, SEL action) {
    UISlider *s = [UISlider new];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [s addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

static UILabel *QMLabel(NSString *text, CGFloat size) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = QMFont(size, NO);
    l.textColor = [UIColor colorWithWhite:1 alpha:0.9];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

static UIScrollView *QMScroll(UIView *content) {
    UIScrollView *sv = [UIScrollView new];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.showsVerticalScrollIndicator = YES;
    sv.alwaysBounceVertical = YES;
    [sv addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:sv.frameLayoutGuide.widthAnchor],
    ]];
    return sv;
}
static UIStackView *QMStack(NSArray *views) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 8;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    return s;
}

#pragma mark - 设置面板

@interface QMPanelController : UIViewController <PHPickerViewControllerDelegate>
@end

@implementation QMPanelController {
    UIView *_panel;
    UILabel *_status;
    UIButton *_tabSettings, *_tabMedia, *_tabLight;
    UIView *_pageSettings, *_pageMedia, *_pageLight;
    QMJoystick *_joystick;
    UISlider *_bri, *_con, *_sat, *_gam;
    UISlider *_inten, *_wscale, *_hscale, *_feather;
    UISegmentedControl *_dirSeg, *_blendSeg;
    UISwitch *_liveSw, *_lightSw, *_pickerSw, *_sceneSw;
    NSInteger _pendingKind;   // 0 图片 1 视频
    NSInteger _pendingSlot;
    NSTimer *_refresh;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _panel = [UIView new];
    _panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    _panel.layer.cornerRadius = 18;
    _panel.clipsToBounds = YES;
    _panel.layer.borderWidth = 1;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_panel];

    _status = QMLabel(@"", 12);
    _status.numberOfLines = 2;
    [_panel addSubview:_status];

    _tabSettings = QMButton(@"设置", self, @selector(tabSettings));
    _tabMedia    = QMButton(@"多图", self, @selector(tabMedia));
    _tabLight    = QMButton(@"打光", self, @selector(tabLight));
    UIStackView *tabs = [[UIStackView alloc] initWithArrangedSubviews:@[_tabSettings, _tabMedia, _tabLight]];
    tabs.axis = UILayoutConstraintAxisHorizontal;
    tabs.distribution = UIStackViewDistributionFillEqually;
    tabs.spacing = 8;
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:tabs];

    UIButton *close = QMButton(@"✕", self, @selector(close));
    [_panel addSubview:close];

    _pageSettings = QMScroll([self buildSettings]);
    _pageMedia    = QMScroll([self buildMedia]);
    _pageLight    = QMScroll([self buildLight]);
    for (UIView *v in @[_pageSettings, _pageMedia, _pageLight]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel addSubview:v];
        v.hidden = (v != _pageSettings);
    }

    UILayoutGuide *g = _panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_panel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_panel.widthAnchor constraintEqualToConstant:340],
        [_panel.heightAnchor constraintEqualToConstant:540],

        [_status.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [_status.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-44],
        [_status.heightAnchor constraintEqualToConstant:30],
        [_status.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],

        [close.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-10],
        [close.topAnchor constraintEqualToAnchor:g.topAnchor constant:6],
        [close.widthAnchor constraintEqualToConstant:34],
        [close.heightAnchor constraintEqualToConstant:34],

        [tabs.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [tabs.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [tabs.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:8],
        [tabs.heightAnchor constraintEqualToConstant:34],
    ]];
    for (UIView *v in @[_pageSettings, _pageMedia, _pageLight]) {
        [NSLayoutConstraint activateConstraints:@[
            [v.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
            [v.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
            [v.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:12],
            [v.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
        ]];
    }

    [self refreshStatus];
    _refresh = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(refreshStatus)
                                             userInfo:nil repeats:YES];
}

- (void)dealloc { [_refresh invalidate]; }

- (void)refreshStatus {
    QMState *st = [QMState shared];
    [st load];
    NSString *lic = [QMLicense shared].statusText;
    NSString *src = st.activePath.lastPathComponent ?: @"未选择";
    _status.text = [NSString stringWithFormat:@"替换:%@  播放:%@  %@\n%@  %@",
                    st.live ? @"开" : @"关", st.paused ? @"暂停" : @"播放", lic, src,
                    [QMLicense shared].deviceFingerprint];
    _liveSw.on = st.live;
    _bri.value = st.brightness; _con.value = st.contrast;
    _sat.value = st.saturation; _gam.value = st.gamma;
}

- (UIView *)buildSettings {
    UIView *page = [UIView new];

    _joystick = [[QMJoystick alloc] initWithFrame:CGRectMake(0, 0, 96, 96)];
    _joystick.translatesAutoresizingMaskIntoConstraints = NO;
    [_joystick.widthAnchor constraintEqualToConstant:96].active = YES;
    [_joystick.heightAnchor constraintEqualToConstant:96].active = YES;
    __weak typeof(self) w = self;
    _joystick.onChange = ^(CGFloat nx, CGFloat ny) {
        QMState *st = [QMState shared];
        st.panX = nx * 0.6;
        st.panY = ny * 0.6;
    };

    _liveSw = [UISwitch new];
    [_liveSw addTarget:self action:@selector(liveChanged:) forControlEvents:UIControlEventValueChanged];

    NSArray *btns = @[
        QMButton(@"镜像", self, @selector(mirrorTapped)),
        QMButton(@"填充", self, @selector(edgeTapped)),
        QMButton(@"复位", self, @selector(resetTapped)),
        QMButton(@"播放/暂停", self, @selector(playPauseTapped)),
        QMButton(@"授权查看", self, @selector(licenseTapped)),
    ];
    UIStackView *btnRow1 = [[UIStackView alloc] initWithArrangedSubviews:@[btns[0], btns[1], btns[2]]];
    btnRow1.axis = UILayoutConstraintAxisHorizontal;
    btnRow1.distribution = UIStackViewDistributionFillEqually;
    btnRow1.spacing = 8;
    UIStackView *btnRow2 = [[UIStackView alloc] initWithArrangedSubviews:@[btns[3], btns[4]]];
    btnRow2.axis = UILayoutConstraintAxisHorizontal;
    btnRow2.distribution = UIStackViewDistributionFillEqually;
    btnRow2.spacing = 8;

    // 98d 同款六键：上/下/左/右/放大/缩小
    NSArray *keys = @[
        QMButton(@"▲", self, @selector(keyUp)),
        QMButton(@"▼", self, @selector(keyDown)),
        QMButton(@"◀", self, @selector(keyLeft)),
        QMButton(@"▶", self, @selector(keyRight)),
        QMButton(@"➕", self, @selector(keyZoomIn)),
        QMButton(@"➖", self, @selector(keyZoomOut)),
    ];
    UIStackView *keyRow = [[UIStackView alloc] initWithArrangedSubviews:keys];
    keyRow.axis = UILayoutConstraintAxisHorizontal;
    keyRow.distribution = UIStackViewDistributionFillEqually;
    keyRow.spacing = 6;
    keyRow.translatesAutoresizingMaskIntoConstraints = NO;

    _bri = QMSlider(self, @selector(colorChanged:)); _bri.minimumValue = -0.5; _bri.maximumValue = 0.5;
    _con = QMSlider(self, @selector(colorChanged:)); _con.minimumValue = 0.5;  _con.maximumValue = 1.6;
    _sat = QMSlider(self, @selector(colorChanged:)); _sat.minimumValue = 0.0;  _sat.maximumValue = 2.0;
    _gam = QMSlider(self, @selector(colorChanged:)); _gam.minimumValue = 0.5;  _gam.maximumValue = 2.0;

    UIStackView *stack = QMStack(@[
        _joystick,
        keyRow,
        QMStack(@[QMLabel(@"亮度", 12), _bri]),
        QMStack(@[QMLabel(@"对比", 12), _con]),
        QMStack(@[QMLabel(@"饱和", 12), _sat]),
        QMStack(@[QMLabel(@"伽马", 12), _gam]),
    ]);
    stack.spacing = 4;
    [page addSubview:stack];
    [page addSubview:btnRow1];
    [page addSubview:btnRow2];
    [page addSubview:_liveSw];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor],

        [_liveSw.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [_liveSw.centerYAnchor constraintEqualToAnchor:btnRow1.centerYAnchor],

        [btnRow1.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [btnRow1.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [btnRow1.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:10],

        [btnRow2.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [btnRow2.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [btnRow2.topAnchor constraintEqualToAnchor:btnRow1.bottomAnchor constant:8],
    ]];
    return page;
}

- (UIView *)buildMedia {
    UIView *page = [UIView new];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [page addSubview:stack];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *img = QMButton([NSString stringWithFormat:@"图片槽 %ld", (long)i + 1], self, @selector(pickImage:));
        img.tag = i;
        UIButton *delImg = QMButton(@"删", self, @selector(delImage:));
        delImg.tag = i;
        UIStackView *r1 = [[UIStackView alloc] initWithArrangedSubviews:@[img, delImg]];
        r1.axis = UILayoutConstraintAxisHorizontal;
        r1.spacing = 8;
        [delImg.widthAnchor constraintEqualToConstant:44].active = YES;

        UIButton *vid = QMButton([NSString stringWithFormat:@"视频槽 %ld", (long)i + 1], self, @selector(pickVideo:));
        vid.tag = i;
        UIButton *delVid = QMButton(@"删", self, @selector(delVideo:));
        delVid.tag = i;
        UIStackView *r2 = [[UIStackView alloc] initWithArrangedSubviews:@[vid, delVid]];
        r2.axis = UILayoutConstraintAxisHorizontal;
        r2.spacing = 8;
        [delVid.widthAnchor constraintEqualToConstant:44].active = YES;

        [rows addObject:r1];
        [rows addObject:r2];
    }
    for (UIView *v in rows) [stack addArrangedSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor],
    ]];
    return page;
}

- (UIView *)buildLight {
    UIView *page = [UIView new];

    _lightSw = [UISwitch new];
    [_lightSw addTarget:self action:@selector(lightToggled:) forControlEvents:UIControlEventValueChanged];
    _pickerSw = [UISwitch new];
    [_pickerSw addTarget:self action:@selector(pickerToggled:) forControlEvents:UIControlEventValueChanged];
    _sceneSw = [UISwitch new];
    [_sceneSw addTarget:self action:@selector(sceneToggled:) forControlEvents:UIControlEventValueChanged];

    _inten = QMSlider(self, @selector(lightChanged:));   _inten.minimumValue = 0; _inten.maximumValue = 1.5;
    _wscale = QMSlider(self, @selector(lightChanged:));  _wscale.minimumValue = 0.4; _wscale.maximumValue = 2.0;
    _hscale = QMSlider(self, @selector(lightChanged:));  _hscale.minimumValue = 0.4; _hscale.maximumValue = 2.0;
    _feather = QMSlider(self, @selector(lightChanged:)); _feather.minimumValue = 0.05; _feather.maximumValue = 1.0;

    _dirSeg = [[UISegmentedControl alloc] initWithItems:@[@"左上", @"上", @"右上", @"左", @"右", @"左下", @"下", @"右下"]];
    [_dirSeg addTarget:self action:@selector(lightChanged:) forControlEvents:UIControlEventValueChanged];
    _blendSeg = [[UISegmentedControl alloc] initWithItems:@[@"柔光", @"叠加", @"滤色", @"线减", @"强光", @"色淡"]];
    [_blendSeg addTarget:self action:@selector(lightChanged:) forControlEvents:UIControlEventValueChanged];

    UIButton *pick = QMButton(@"屏幕取色", self, @selector(screenPickTapped));

    UIStackView *stack = QMStack(@[
        QMStack(@[QMLabel(@"启用打光", 12), _lightSw]),
        QMStack(@[QMLabel(@"屏幕取色", 12), _pickerSw]),
        QMStack(@[QMLabel(@"场景自适应", 12), _sceneSw]),
        QMLabel(@"强度", 12), _inten,
        QMLabel(@"横向", 12), _wscale,
        QMLabel(@"纵向", 12), _hscale,
        QMLabel(@"羽化", 12), _feather,
        QMLabel(@"光照方向", 12), _dirSeg,
        QMLabel(@"混合模式", 12), _blendSeg,
        pick,
    ]);
    [page addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor],
    ]];
    return page;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    QMLightState *ls = [QMLightState shared];
    [ls reloadFromDisk];
    _lightSw.on = ls.enabled; _pickerSw.on = ls.screenPicker; _sceneSw.on = ls.sceneAdaptive;
    _inten.value = ls.intensity; _wscale.value = ls.widthScale;
    _hscale.value = ls.heightScale; _feather.value = ls.feather;
    _dirSeg.selectedSegmentIndex = MAX(0, MIN(7, ls.direction));
    _blendSeg.selectedSegmentIndex = MAX(0, MIN(5, ls.blendMode));
}

#pragma mark 动作

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)tabSettings { _pageSettings.hidden = NO; _pageMedia.hidden = YES; _pageLight.hidden = YES; }
- (void)tabMedia    { _pageSettings.hidden = YES; _pageMedia.hidden = NO;  _pageLight.hidden = YES; }
- (void)tabLight    { _pageSettings.hidden = YES; _pageMedia.hidden = YES; _pageLight.hidden = NO;  }

- (void)liveChanged:(UISwitch *)sw {
    QMState *st = [QMState shared];
    st.live = sw.isOn;
    if (sw.isOn) [[QMCore shared] setActive:YES reason:@"ui toggle"];
    else [[QMCore shared] setActive:NO reason:@"ui toggle"];
    [self refreshStatus];
}
- (void)mirrorTapped { QMState *st = [QMState shared]; st.mirror = !st.mirror; [self refreshStatus]; }
- (void)edgeTapped   { QMState *st = [QMState shared]; st.edgeClamp = !st.edgeClamp; [self refreshStatus]; }
- (void)resetTapped  {
    QMState *st = [QMState shared];
    st.panX = st.panY = 0; st.zoom = 1.0; st.mirror = NO;
    st.brightness = 0; st.contrast = 1; st.saturation = 1; st.gamma = 1;
    _joystick.nx = _joystick.ny = 0;
    [_joystick setNeedsDisplay];
    [self refreshStatus];
    QMLog(@"[vcam][btn] resetEdits: zoom/pan/rotation/mirror 已复位");
}
- (void)playPauseTapped { [[QMCore shared] togglePause]; [self refreshStatus]; }
- (void)colorChanged:(UISlider *)s {
    QMState *st = [QMState shared];
    st.brightness = _bri.value; st.contrast = _con.value;
    st.saturation = _sat.value; st.gamma = _gam.value;
}

#pragma mark 六键

- (void)keyUp    { QMState *st = [QMState shared]; st.panY = MAX(-1.0, st.panY - 0.05); }
- (void)keyDown  { QMState *st = [QMState shared]; st.panY = MIN(1.0,  st.panY + 0.05); }
- (void)keyLeft  { QMState *st = [QMState shared]; st.panX = MAX(-1.0, st.panX - 0.05); }
- (void)keyRight { QMState *st = [QMState shared]; st.panX = MIN(1.0,  st.panX + 0.05); }
- (void)keyZoomIn  { QMState *st = [QMState shared]; st.zoom = MIN(6.0, st.zoom + 0.1); }
- (void)keyZoomOut { QMState *st = [QMState shared]; st.zoom = MAX(0.2, st.zoom - 0.1); }

- (void)licenseTapped {
    QMLicense *lic = [QMLicense shared];
    NSString *info = [NSString stringWithFormat:@"%@\n\n设备指纹（发给客服）\n%@",
                      lic.statusText, lic.deviceFingerprint];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"设备授权信息"
                                                              message:info
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"粘贴从发码方收到的激活码（约 180 字符）";
        tf.font = [UIFont systemFontOfSize:11];
        tf.textContentType = nil;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"提交" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *code = ac.textFields.firstObject.text;
        NSString *msg = nil;
        QMLicenseStatus st = [lic activateWithCode:code message:&msg];
        UIAlertController *r = [UIAlertController alertControllerWithTitle:(st == QMLicenseStatusOK ? @"激活成功" : @"激活失败")
                                                                   message:msg ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:r animated:YES completion:nil];
        [self refreshStatus];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"复制指纹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = lic.deviceFingerprint;
        QMLog(@"[vcam] 指纹已复制到剪贴板");
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清除激活信息" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [lic clearLicense];
        [self refreshStatus];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)lightToggled:(UISwitch *)s { [QMLightState shared].enabled = s.isOn; }
- (void)pickerToggled:(UISwitch *)s {
    [QMLightState shared].screenPicker = s.isOn;
    if (s.isOn) [[QMLighting shared] pickScreenColor];
}
- (void)sceneToggled:(UISwitch *)s { [QMLightState shared].sceneAdaptive = s.isOn; }
- (void)lightChanged:(id)s {
    QMLightState *ls = [QMLightState shared];
    ls.intensity = _inten.value; ls.widthScale = _wscale.value;
    ls.heightScale = _hscale.value; ls.feather = _feather.value;
    ls.direction = _dirSeg.selectedSegmentIndex; ls.blendMode = _blendSeg.selectedSegmentIndex;
}
- (void)screenPickTapped { [[QMLighting shared] pickScreenColor]; }

#pragma mark 相册

- (void)_presentPicker:(NSInteger)kind slot:(NSInteger)slot {
    _pendingKind = kind; _pendingSlot = slot;
    PHPickerConfiguration *cfg = [PHPickerConfiguration new];
    cfg.selectionLimit = 1;
    cfg.filter = (kind == 0) ? PHPickerFilter.imagesFilter : PHPickerFilter.videosFilter;
    PHPickerViewController *vc = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    vc.delegate = self;
    [self presentViewController:vc animated:YES completion:nil];
}
- (void)pickImage:(UIButton *)b { [self _presentPicker:0 slot:b.tag]; }
- (void)pickVideo:(UIButton *)b { [self _presentPicker:1 slot:b.tag]; }

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!results.count) return;
    NSItemProvider *prov = results.firstObject.itemProvider;
    NSString *dir = (_pendingKind == 0) ? QMPath(QMV_SLOT_IMAGE_DIR) : QMPath(QMV_SLOT_VIDEO_DIR);
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    NSString *ext = (_pendingKind == 0) ? @"jpg" : @"mov";
    NSString *dst = [dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%ld.%@", (long)_pendingSlot + 1, ext]];

    NSString *uti = (_pendingKind == 0) ? @"public.image" : @"public.movie";
    [prov loadFileRepresentationForTypeIdentifier:uti completionHandler:^(NSURL *url, NSError *err) {
        if (url) {
            [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
            NSError *e2 = nil;
            [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:&e2];
            if (e2) QMLog(@"[vcam] copy failed: %@", e2);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            QMState *st = [QMState shared];
            st.mediaKind = (self->_pendingKind == 0) ? @"image" : @"video";
            st.slotIndex = self->_pendingSlot;
            st.activePath = dst;
            [[QMCore shared] reloadMedia];
            [self refreshStatus];
        });
    }];
}

- (void)_deleteSlot:(NSInteger)slot kind:(NSInteger)kind {
    NSString *dir = (kind == 0) ? QMPath(QMV_SLOT_IMAGE_DIR) : QMPath(QMV_SLOT_VIDEO_DIR);
    NSString *prefix = [NSString stringWithFormat:@"%ld.", (long)slot + 1];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        if ([f hasPrefix:prefix]) {
            [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
        }
    }
    QMLog(@"[vcam] 已删除%@槽位 %ld", kind == 0 ? @"图片" : @"视频", (long)slot + 1);
    [[QMCore shared] reloadMedia];
}
- (void)delImage:(UIButton *)b { [self _deleteSlot:b.tag kind:0]; }
- (void)delVideo:(UIButton *)b { [self _deleteSlot:b.tag kind:1]; }

@end

#pragma mark - 悬浮窗管理

@interface QMSpringBoardUI : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) QMFloatingBall *ball;
@property (nonatomic, strong) QMPanelController *panel;
+ (instancetype)shared;
- (void)install;
- (void)showPanel;
- (void)togglePanel;
@end

@interface QMPassWindow : UIWindow
@end

@implementation QMPassWindow
// 空白处放行给 SpringBoard，只有球/面板这些子视图接收触摸
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

@implementation QMSpringBoardUI

+ (instancetype)shared {
    static QMSpringBoardUI *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [QMSpringBoardUI new]; });
    return s;
}

- (UIWindowScene *)_scene {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *sc in app.connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] &&
            sc.activationState != UISceneActivationStateBackground) {
            return (UIWindowScene *)sc;
        }
    }
    for (UIScene *sc in app.connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)sc;
    }
    for (UIWindow *w in app.windows) {
        if (w.windowScene) return w.windowScene;
    }
    return nil;
}

- (void)install {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) return;
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Media/DCIM/.qm_safe"]) {
            QMLog(@"[vcam] .qm_safe present, UI disabled");
            QMBeacon(@"UI disabled by .qm_safe");
            return;
        }
        UIWindowScene *scene = [self _scene];
        QMBeacon(@"UI install: scenes=%lu scene=%p", (unsigned long)[UIApplication sharedApplication].connectedScenes.count, scene);
        if (!scene) {
            QMLog(@"[vcam] no foreground UIWindowScene yet, retry in 1s");
            QMBeacon(@"UI: no scene, retry");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self install];
            });
            return;
        }
        self.window = [[QMPassWindow alloc] initWithWindowScene:scene];
        self.window.frame = scene.coordinateSpace.bounds;
        self.window.windowLevel = 20000000;   // 高于 SpringBoard 全部系统窗口
        self.window.backgroundColor = [UIColor clearColor];
        self.window.rootViewController = [UIViewController new];
        self.window.rootViewController.view.backgroundColor = [UIColor clearColor];
        self.window.hidden = NO;

        CGFloat side = 54;
        CGRect f = CGRectMake(scene.coordinateSpace.bounds.size.width - side - 14,
                              scene.coordinateSpace.bounds.size.height * 0.42, side, side);
        self.ball = [[QMFloatingBall alloc] initWithFrame:f];
        __weak typeof(self) w = self;
        self.ball.onTap = ^{ [w togglePanel]; };
        self.ball.onLongPress = ^{
            QMState *st = [QMState shared];
            st.live = !st.live;
            [[QMCore shared] setActive:st.live reason:@"long press"];
        };
        [self.window.rootViewController.view addSubview:self.ball];
        QMBeacon(@"UI: ball created at %@ level=%.0f", NSStringFromCGRect(f), self.window.windowLevel);
        QMLog(@"[vcam] Floating window created");
    });
}

- (void)showPanel {
    if (self.panel.presentingViewController) return;
    QMPanelController *p = [QMPanelController new];
    p.modalPresentationStyle = UIModalPresentationOverFullScreen;
    p.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    self.panel = p;
    UIViewController *root = self.window.rootViewController;
    [root presentViewController:p animated:YES completion:nil];
}

- (void)togglePanel {
    if (self.panel.presentingViewController) {
        [self.panel dismissViewControllerAnimated:YES completion:nil];
        self.panel = nil;
    } else {
        [self showPanel];
    }
}

@end

#pragma mark - SpringBoard hooks

static void (*orig_handlePhysicalButton)(id, SEL, id);
static void (*orig_increaseVolume)(id, SEL);

static NSTimeInterval gLastVolumeUp = 0;

static void qm_volume_up(void) {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gLastVolumeUp < 0.45) {
        QMLog(@"[vcam] Double click volume UP detected!");
        dispatch_async(dispatch_get_main_queue(), ^{ [[QMSpringBoardUI shared] togglePanel]; });
        gLastVolumeUp = 0;
    } else {
        gLastVolumeUp = now;
    }
}

static void qm_handlePhysicalButton(id self, SEL _cmd, id ev) {
    if (orig_handlePhysicalButton) orig_handlePhysicalButton(self, _cmd, ev);
}

static void qm_increaseVolume(id self, SEL _cmd) {
    qm_volume_up();
    if (orig_increaseVolume) orig_increaseVolume(self, _cmd);
}

static void (*orig_appDidFinishLaunching)(id, SEL, id);
static void qm_appDidFinishLaunching(id self, SEL _cmd, id app) {
    if (orig_appDidFinishLaunching) orig_appDidFinishLaunching(self, _cmd, app);
    [[QMSpringBoardUI shared] install];
}

void QMInstallSpringBoardHooks(void) {
    Class sb = objc_getClass("SpringBoard");
    if (sb) {
        Method m = class_getInstanceMethod(sb, @selector(_handlePhysicalButtonEvent:));
        if (m) QMHookMessage(sb, @selector(_handlePhysicalButtonEvent:),
                               (IMP)qm_handlePhysicalButton, (IMP *)&orig_handlePhysicalButton);
        Method m2 = class_getInstanceMethod(sb, @selector(applicationDidFinishLaunching:));
        if (m2) QMHookMessage(sb, @selector(applicationDidFinishLaunching:),
                                (IMP)qm_appDidFinishLaunching, (IMP *)&orig_appDidFinishLaunching);
        QMLog(@"[vcam] SpringBoard hooks initialized");
    }

    Class vc = objc_getClass("VolumeControl");
    if (vc && class_getInstanceMethod(vc, @selector(increaseVolume))) {
        QMHookMessage(vc, @selector(increaseVolume), (IMP)qm_increaseVolume, (IMP *)&orig_increaseVolume);
        QMLog(@"[vcam] VolumeControl hook installed");
    }
    [[QMSpringBoardUI shared] install];
}

void QMShowPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[QMSpringBoardUI shared] showPanel]; });
}
