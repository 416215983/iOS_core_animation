//
//  RotateRect.m
//  animatedPageControl
//
//  Created by Jack on 16/8/13.
//  Copyright © 2016年 Jack. All rights reserved.
//

#import "RotateRect.h"
#import "AnimatedPageControl.h"

static CGPathRef createPathRotatedAroundBoundingBoxCenter(CGPathRef path, CGFloat radians)
{
    CGRect bounds = CGPathGetBoundingBox(path); // might want to use CGPathGetPathBoundingBox
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformTranslate(transform, center.x, center.y);
    transform = CGAffineTransformRotate(transform, radians);
    transform = CGAffineTransformTranslate(transform, -center.x, -center.y);
    return CGPathCreateCopyByTransformingPath(path, &transform);
}

@interface RotateRect ()

@property(nonatomic,assign)CGRect currentRect;

@end


@implementation RotateRect
{
    CGFloat index;
}


#pragma mark - Initialize

-(id)init{
    self = [super init];
    if (self) {
        
    }
    return self;
}

-(id)initWithLayer:(RotateRect *)layer{
    self = [super initWithLayer:layer];
    if (self) {
        
        self.indicatorSize = layer.indicatorSize;
        
    }
    return self;
}

#pragma mark - override

- (void)drawInContext:(CGContextRef)ctx
{
    UIBezierPath *rectPath = [UIBezierPath bezierPathWithRect:self.currentRect];
    CGPathRef path = createPathRotatedAroundBoundingBoxCenter(rectPath.CGPath, index * M_PI * 2);
    rectPath.CGPath = path;
    CGContextAddPath(ctx, path);
    CGContextSetFillColorWithColor(ctx, self.indicatorColor.CGColor);
    CGContextFillPath(ctx);

    CGPathRelease(path);
}

- (void)animateIndicatorWithScrollView:(UIScrollView *)scrollView
                          andIndicator:(AnimatedPageControl *)pgctl
{
    CGFloat originX = (scrollView.contentOffset.x / scrollView.frame.size.width) * (pgctl.frame.size.width / (pgctl.pageCount-1));
    index = (scrollView.contentOffset.x / scrollView.frame.size.width) / (pgctl.pageCount - 1);
    
    if (originX - self.indicatorSize/2 <= 0) {
        self.currentRect = CGRectMake(0, self.frame.size.height/2-self.indicatorSize/2, self.indicatorSize, self.indicatorSize);
    }else if ((originX - self.indicatorSize/2) >= self.frame.size.width - self.indicatorSize){
        self.currentRect = CGRectMake(self.frame.size.width - self.indicatorSize, self.frame.size.height/2-self.indicatorSize/2, self.indicatorSize, self.indicatorSize);
    }else{
        self.currentRect = CGRectMake(originX - self.indicatorSize/2, self.frame.size.height/2-self.indicatorSize/2, self.indicatorSize, self.indicatorSize);
    }
    
    [self setNeedsDisplay];
    
}








@end
