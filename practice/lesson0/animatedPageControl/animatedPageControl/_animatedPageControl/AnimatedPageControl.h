//
//  AnimatedPageControl.h
//  animatedPageControl
//
//  Created by Jack on 16/8/13.
//  Copyright © 2016年 Jack. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Indicator.h"
#import "Line.h"

typedef enum : NSUInteger
{
    IndicatorStyleGooeyCircle, // 0
    IndicatorStyleRotateRect,  // 1
} IndicatorStyle;


@interface AnimatedPageControl : UIView

//----READWRITE----
//page的个数 The count of all pages
@property(nonatomic, assign) NSInteger pageCount;

//第一次显示的page 第一页为1,类推 2,3,4...  The default selected page ,if you
//wanna show fourth page, set 4
@property(nonatomic, assign) NSInteger selectedPage;

//未选中的颜色
@property(nonatomic, strong) UIColor *unSelectedColor;

//选中的颜色
@property(nonatomic, strong) UIColor *selectedColor;

//是否显示填充进度条
@property(nonatomic, assign) BOOL shouldShowProgressLine;

//绑定的滚动视图
@property(nonatomic, strong) UIScrollView *bindScrollView;

// Possible to swipe (Pan gesture recognize)
@property(nonatomic, assign) BOOL swipeEnable;

// Indicator样式
@property(nonatomic, assign) IndicatorStyle indicatorStyle;

// Indicator大小
@property(nonatomic, assign) CGFloat indicatorSize;

// Indicator 只读!  Readonly!
@property(nonatomic, strong) Indicator *indicator;

//-----READONLY-----
//直线Layer
@property(nonatomic, readonly) Line *pageControlLine;

// Animate to index
- (void)animateToIndex:(NSInteger)index;
@end
