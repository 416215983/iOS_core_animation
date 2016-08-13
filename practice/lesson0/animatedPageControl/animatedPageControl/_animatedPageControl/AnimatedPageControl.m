//
//  AnimatedPageControl.m
//  animatedPageControl
//
//  Created by Jack on 16/8/13.
//  Copyright © 2016年 Jack. All rights reserved.
//

#import "AnimatedPageControl.h"
#import "GooeyCircle.h"
#import "RotateRect.h"

@interface AnimatedPageControl ()

@property(nonatomic,strong)Line *line;
//Indicator-STYLE
@property(nonatomic,strong)GooeyCircle *gooeyCircle;
@property(nonatomic,strong)RotateRect  *rotateRect;

@end

@implementation AnimatedPageControl


-(id)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapAction:)];
        [self addGestureRecognizer:tap];
        
    }
    return self;
}


#pragma mark - PUBLIC Method


-(void)display{
    
    self.line = [Line layer];
    self.line.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
    self.line.pageCount = self.pageCount;
    self.line.selectedPage = 1;
    self.line.unSelectedColor = self.unSelectedColor;
    self.line.selectedColor = self.selectedColor;
    self.line.bindScrollView = self.bindScrollView;
    
    self.line.contentsScale = [UIScreen mainScreen].scale;
    [self.line setNeedsDisplay];
    [self.layer addSublayer:self.line];
    [self addIndicator];
}

-(Line *)pageControlLine{
    return self.line;
}


#pragma mark - PRIVATE Method


-(void)addIndicator{
    switch (self.indicatorStyle) {
        case IndicatorStyleGooeyCircle:
            
            self.indicator = self.gooeyCircle;
            break;
            
        case IndicatorStyleRotateRect:
            
            self.rotateRect = [RotateRect layer];
            self.indicator = self.rotateRect;
            self.rotateRect.indicatorColor = self.selectedColor;
            
            self.rotateRect.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
            self.rotateRect.indicatorSize  = self.indicatorSize;
            self.rotateRect.contentsScale = [UIScreen mainScreen].scale;
            [self.rotateRect animateIndicatorWithScrollView:self.bindScrollView andIndicator:self];
            [self.layer insertSublayer:self.rotateRect above:self.line];
            self.layer.masksToBounds = NO;
            
            break;
            
        default:
            break;
    }
}

#pragma mark - UITapGestureRecognizer tapAction

-(void)tapAction:(UITapGestureRecognizer *)ges
{
    NSAssert(self.bindScrollView != nil, @"You can not scroll without assigning bindScrollView");
    
    CGPoint location = [ges locationInView:self];
    if (CGRectContainsPoint(self.line.frame, location)) {
        CGFloat ballDistance = self.frame.size.width / (self.pageCount - 1);
        NSInteger index =  location.x / ballDistance;
        if ((location.x - index*ballDistance) >= ballDistance/2) {
            index += 1;
        }
        
        [self.line animateSelectedLineToNewIndex:index+1];
        [self.bindScrollView setContentOffset:CGPointMake(self.bindScrollView.frame.size.width *index, 0) animated:YES];
        NSLog(@"DidSelected index:%ld",(long)index+1);
    }
}



@end
