#图像IO
##加载和潜伏
绘图实际消耗的时间通常并不是影响性能的因素。图片消耗很大一部分内存，而且不太可能把需要显示的图片都保留在内存中，所以需要在应用运行的时候周期性地加载和卸载图片。

图片文件加载的速度被CPU和IO（输入/输出）同时影响。iOS设备中的闪存已经比传统硬盘快很多了，但仍然比RAM慢将近200倍左右，这就需要很小心地管理加载，来避免延迟。

只要有可能，试着在程序生命周期不易察觉的时候来加载图片，例如启动，或者在屏幕切换的过程中。按下按钮和按钮响应事件之间最大的延迟大概是200ms，这比动画每一帧切换的16ms小得多。你可以在程序首次启动的时候加载图片，但是如果20秒内无法启动程序的话，iOS检测计时器就会终止你的应用（而且如果启动大于2，3秒的话用户就会抱怨了）。

有些时候，提前加载所有的东西并不明智。比如说包含上千张图片的图片传送带：用户希望能够能够平滑快速翻动图片，所以就不可能提前预加载所有图片；那样会消耗太多的时间和内存。

有时候图片也需要从远程网络连接中下载，这将会比从磁盘加载要消耗更多的时间，甚至可能由于连接问题而加载失败（在几秒钟尝试之后）。你不能够在主线程中加载网络造成等待，所以需要后台线程。

###线程加载

在“性能调优”我们的联系人列表例子中，图片都非常小，所以可以在主线程同步加载。但是对于大图来说，这样做就不太合适了，因为加载会消耗很长时间，造成滑动的不流畅。滑动动画会在主线程的run loop中更新，所以会有更多运行在渲染服务进程中CPU相关的性能问题。



```

#import "ViewController.h"

@interface ViewController() 

@property (nonatomic, copy) NSArray *imagePaths;
@property (nonatomic, weak) IBOutlet UICollectionView *collectionView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    //set up data
    self.imagePaths =
    [[NSBundle mainBundle] pathsForResourcesOfType:@"png" inDirectory:@"Vacation Photos"];
    //register cell class
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.imagePaths count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    //dequeue cell
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];

    //add image view
    const NSInteger imageTag = 99;
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:imageTag];
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithFrame: cell.contentView.bounds];
        imageView.tag = imageTag;
        [cell.contentView addSubview:imageView];
    }
    //set image
    NSString *imagePath = self.imagePaths[indexPath.row];
    imageView.image = [UIImage imageWithContentsOfFile:imagePath];
    return cell;
}

@end
```

![](lesson13_0.jpeg)

传送器中的图片尺寸为800x600像素的PNG，对iPhone5来说，1/60秒要加载大概700KB左右的图片。当传送器滚动的时候，图片也在实时加载，于是（预期中的）卡动就发生了。时间分析工具（图14.2）显示了很多时间都消耗在了UIImage的+imageWithContentsOfFile:方法中了。很明显，图片加载造成了瓶颈。

![](lesson13_1.jpeg)
这里提升性能唯一的方式就是在另一个线程中加载图片。这并不能够降低实际的加载时间（可能情况会更糟，因为系统可能要消耗CPU时间来处理加载的图片数据），但是主线程能够有时间做一些别的事情，比如响应用户输入，以及滑动动画。

为了在后台线程加载图片，我们可以使用GCD或者NSOperationQueue创建自定义线程，或者使用CATiledLayer。为了从远程网络加载图片，我们可以使用异步的NSURLConnection，但是对本地存储的图片，并不十分有效。

###GCD和NSOperationQueue
GCD（Grand Central Dispatch）和NSOperationQueue很类似，都给我们提供了队列闭包块来在线程中按一定顺序来执行。NSOperationQueue有一个Objecive-C接口（而不是使用GCD的全局C函数），同样在操作优先级和依赖关系上提供了很好的粒度控制，但是需要更多地设置代码。

显示了在低优先级的后台队列而不是主线程使用GCD加载图片的-collectionView:cellForItemAtIndexPath:方法，然后当需要加载图片到视图的时候切换到主线程，因为在后台线程访问视图会有安全隐患。
    
由于视图在UICollectionView会被循环利用，我们加载图片的时候不能确定是否被不同的索引重新复用。为了避免图片加载到错误的视图中，我们在加载前把单元格打上索引的标签，然后在设置图片的时候检测标签是否发生了改变。

```
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                    cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    //dequeue cell
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell"
                                                                           forIndexPath:indexPath];
    //add image view
    const NSInteger imageTag = 99;
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:imageTag];
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithFrame: cell.contentView.bounds];
        imageView.tag = imageTag;
        [cell.contentView addSubview:imageView];
    }
    //tag cell with index and clear current image
    cell.tag = indexPath.row;
    imageView.image = nil;
    //switch to background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        //load image
        NSInteger index = indexPath.row;
        NSString *imagePath = self.imagePaths[index];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        //set image on main thread, but only if index still matches up
        dispatch_async(dispatch_get_main_queue(), ^{
            if (index == cell.tag) {
                imageView.image = image; }
        });
    });
    return cell;
}
```

当运行更新后的版本，性能比之前不用线程的版本好多了，但仍然并不完美。

我们可以看到+imageWithContentsOfFile:方法并不在CPU时间轨迹的最顶部，所以我们的确修复了延迟加载的问题。问题在于我们假设传送器的性能瓶颈在于图片文件的加载，但实际上并不是这样。加载图片数据到内存中只是问题的第一部分。

![](lesson13_2.jpeg)

###延迟解压
 一旦图片文件被加载就必须要进行解码，解码过程是一个相当复杂的任务，需要消耗非常长的时间。解码后的图片将同样使用相当大的内存。

用于加载的CPU时间相对于解码来说根据图片格式而不同。对于PNG图片来说，加载会比JPEG更长，因为文件可能更大，但是解码会相对较快，而且Xcode会把PNG图片进行解码优化之后引入工程。JPEG图片更小，加载更快，但是解压的步骤要消耗更长的时间，因为JPEG解压算法比基于zip的PNG算法更加复杂。

当加载图片的时候，iOS通常会延迟解压图片的时间，直到加载到内存之后。这就会在准备绘制图片的时候影响性能，因为需要在绘制之前进行解压（通常是消耗时间的问题所在）。

最简单的方法就是使用UIImage的+imageNamed:方法避免延时加载。不像+imageWithContentsOfFile:（和其他别的UIImage加载方法），这个方法会在加载图片之后立刻进行解压（就和本章之前我们谈到的好处一样）。问题在于+imageNamed:只对从应用资源束中的图片有效，所以对用户生成的图片内容或者是下载的图片就没法使用了。

另一种立刻加载图片的方法就是把它设置成图层内容，或者是UIImageView的image属性。不幸的是，这又需要在主线程执行，所以不会对性能有所提升。

第三种方式就是绕过UIKit，像下面这样使用ImageIO框架：

```
NSInteger index = indexPath.row;
NSURL *imageURL = [NSURL fileURLWithPath:self.imagePaths[index]];
NSDictionary *options = @{(__bridge id)kCGImageSourceShouldCache: @YES}; 
CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)imageURL, NULL);
CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0,(__bridge CFDictionaryRef)options);
UIImage *image = [UIImage imageWithCGImage:imageRef]; 
CGImageRelease(imageRef);
CFRelease(source);
```

这样就可以使用kCGImageSourceShouldCache来创建图片，强制图片立刻解压，然后在图片的生命周期保留解压后的版本。


最后一种方式就是使用UIKit加载图片，但是立刻会知道CGContext中去。图片必须要在绘制之前解压，所以就强制了解压的及时性。这样的好处在于绘制图片可以再后台线程（例如加载本身）执行，而不会阻塞UI。

有两种方式可以为强制解压提前渲染图片：

* 将图片的一个像素绘制成一个像素大小的CGContext。这样仍然会解压整张图片，但是绘制本身并没有消耗任何时间。这样的好处在于加载的图片并不会在特定的设备上为绘制做优化，所以可以在任何时间点绘制出来。同样iOS也就可以丢弃解压后的图片来节省内存了。
* 将整张图片绘制到CGContext中，丢弃原始的图片，并且用一个从上下文内容中新的图片来代替。这样比绘制单一像素那样需要更加复杂的计算，但是因此产生的图片将会为绘制做优化，而且由于原始压缩图片被抛弃了，iOS就不能够随时丢弃任何解压后的图片来节省内存了。

需要注意的是苹果特别推荐了不要使用这些诡计来绕过标准图片解压逻辑（所以也是他们选择用默认处理方式的原因），但是如果你使用很多大图来构建应用，那如果想提升性能，就只能和系统博弈了。

如果不使用+imageNamed:，那么把整张图片绘制到CGContext可能是最佳的方式了。尽管你可能认为多余的绘制相较别的解压技术而言性能不是很高，但是新创建的图片（在特定的设备上做过优化）可能比原始图片绘制的更快。

 同样，如果想显示图片到比原始尺寸小的容器中，那么一次性在后台线程重新绘制到正确的尺寸会比每次显示的时候都做缩放会更有效（尽管在这个例子中我们加载的图片呈现正确的尺寸，所以不需要多余的优化）。

如果修改了-collectionView:cellForItemAtIndexPath:方法来重绘图片，你会发现滑动更加平滑。

```
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
￼{
    //dequeue cell
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
    ...
    //switch to background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        //load image
        NSInteger index = indexPath.row;
        NSString *imagePath = self.imagePaths[index];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        //redraw image using device context
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, YES, 0);
        [image drawInRect:imageView.bounds];
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        //set image on main thread, but only if index still matches up
        dispatch_async(dispatch_get_main_queue(), ^{
            if (index == cell.tag) {
                imageView.image = image;
            }
        });
    });
    return cell;
}
```
###CATiledLayer

 如第6章“专用图层”中的例子所示，CATiledLayer可以用来异步加载和显示大型图片，而不阻塞用户输入。但是我们同样可以使用CATiledLayer在UICollectionView中为每个表格创建分离的CATiledLayer实例加载传动器图片，每个表格仅使用一个图层。
    
这样使用CATiledLayer有几个潜在的弊端：

* CATiledLayer的队列和缓存算法没有暴露出来，所以我们只能祈祷它能匹配我们的需求。
* CATiledLayer需要我们每次重绘图片到CGContext中，即使它已经解压缩，而且和我们单元格尺寸一样（因此可以直接用作图层内容，而不需要重绘）。

```
#import "ViewController.h"
#import 

@interface ViewController() 

@property (nonatomic, copy) NSArray *imagePaths;
@property (nonatomic, weak) IBOutlet UICollectionView *collectionView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    //set up data
    self.imagePaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"jpg" inDirectory:@"Vacation Photos"];
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.imagePaths count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    //dequeue cell
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
    //add the tiled layer
    CATiledLayer *tileLayer = [cell.contentView.layer.sublayers lastObject];
    if (!tileLayer) {
        tileLayer = [CATiledLayer layer];
        tileLayer.frame = cell.bounds;
        tileLayer.contentsScale = [UIScreen mainScreen].scale;
        tileLayer.tileSize = CGSizeMake(cell.bounds.size.width * [UIScreen mainScreen].scale, cell.bounds.size.height * [UIScreen mainScreen].scale);
        tileLayer.delegate = self;
        [tileLayer setValue:@(indexPath.row) forKey:@"index"];
        [cell.contentView.layer addSublayer:tileLayer];
    }
    //tag the layer with the correct index and reload
    tileLayer.contents = nil;
    [tileLayer setValue:@(indexPath.row) forKey:@"index"];
    [tileLayer setNeedsDisplay];
    return cell;
}

- (void)drawLayer:(CATiledLayer *)layer inContext:(CGContextRef)ctx
{
    //get image index
    NSInteger index = [[layer valueForKey:@"index"] integerValue];
    //load tile image
    NSString *imagePath = self.imagePaths[index];
    UIImage *tileImage = [UIImage imageWithContentsOfFile:imagePath];
    //calculate image rect
    CGFloat aspectRatio = tileImage.size.height / tileImage.size.width;
    CGRect imageRect = CGRectZero;
    imageRect.size.width = layer.bounds.size.width;
    imageRect.size.height = layer.bounds.size.height * aspectRatio;
    imageRect.origin.y = (layer.bounds.size.height - imageRect.size.height)/2;
    //draw tile
    UIGraphicsPushContext(ctx);
    [tileImage drawInRect:imageRect];
    UIGraphicsPopContext();
}

@end
```

需要解释几点：

* CATiledLayer的tileSize属性单位是像素，而不是点，所以为了保证瓦片和表格尺寸一致，需要乘以屏幕比例因子。
* 在`-drawLayer:inContext:`方法中，我们需要知道图层属于哪一个indexPath以加载正确的图片。这里我们利用了CALayer的KVC来存储和检索任意的值，将图层和索引打标签。

结果CATiledLayer工作的很好，性能问题解决了，而且和用GCD实现的代码量差不多。仅有一个问题在于图片加载到屏幕上后有一个明显的淡入。

![](lesson13_3.jpeg)

 我们可以调整CATiledLayer的fadeDuration属性来调整淡入的速度，或者直接将整个渐变移除，但是这并没有根本性地去除问题：在图片加载到准备绘制的时候总会有一个延迟，这将会导致滑动时候新图片的跳入。这并不是CATiledLayer的问题，使用GCD的版本也有这个问题。

即使使用上述我们讨论的所有加载图片和缓存的技术，有时候仍然会发现实时加载大图还是有问题。就和13章中提到的那样，iPad上一整个视网膜屏图片分辨率达到了2048x1536，而且会消耗12MB的RAM（未压缩）。第三代iPad的硬件并不能支持1/60秒的帧率加载，解压和显示这种图片。即使用后台线程加载来避免动画卡顿，仍然解决不了问题。

我们可以在加载的同时显示一个占位图片，但这并没有根本解决问题，我们可以做到更好。

###分辨率交换

视网膜分辨率（根据苹果市场定义）代表了人的肉眼在正常视角距离能够分辨的最小像素尺寸。但是这只能应用于静态像素。当观察一个移动图片时，你的眼睛就会对细节不敏感，于是一个低分辨率的图片和视网膜质量的图片没什么区别了。

如果需要快速加载和显示移动大图，简单的办法就是欺骗人眼，在移动传送器的时候显示一个小图（或者低分辨率），然后当停止的时候再换成大图。这意味着我们需要对每张图片存储两份不同分辨率的副本，但是幸运的是，由于需要同时支持Retina和非Retina设备，本来这就是普遍要做到的。

如果从远程源或者用户的相册加载没有可用的低分辨率版本图片，那就可以动态将大图绘制到较小的CGContext，然后存储到某处以备复用。

为了做到图片交换，我们需要利用UIScrollView的一些实现UIScrollViewDelegate协议的委托方法（和其他类似于UITableView和UICollectionView基于滚动视图的控件一样）：

```
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;  
```
你可以使用这几个方法来检测传送器是否停止滚动，然后加载高分辨率的图片。只要高分辨率图片和低分辨率图片尺寸颜色保持一致，你会很难察觉到替换的过程（确保在同一台机器使用相同的图像程序或者脚本生成这些图片）。


##缓存

如果有很多张图片要显示，最好不要提前把所有都加载进来，而是应该当移出屏幕之后立刻销毁。通过选择性的缓存，你就可以避免来回滚动时图片重复性的加载了。

缓存其实很简单：就是存储昂贵计算后的结果（或者是从闪存或者网络加载的文件）在内存中，以便后续使用，这样访问起来很快。问题在于缓存本质上是一个权衡过程 - 为了提升性能而消耗了内存，但是由于内存是一个非常宝贵的资源，所以不能把所有东西都做缓存。

何时将何物做缓存（做多久）并不总是很明显。幸运的是，大多情况下，iOS都为我们做好了图片的缓存。

***+imageNamed:方法***

之前我们提到使用[UIImage imageNamed:]加载图片有个好处在于可以立刻解压图片而不用等到绘制的时候。但是[UIImage imageNamed:]方法有另一个非常显著的好处：它在内存中自动缓存了解压后的图片，即使你自己没有保留对它的任何引用。

对于iOS应用那些主要的图片（例如图标，按钮和背景图片），使用[UIImage imageNamed:]加载图片是最简单最有效的方式。在nib文件中引用的图片同样也是这个机制，所以你很多时候都在隐式的使用它。

但是`[UIImage imageNamed:]`并不适用任何情况。它为用户界面做了优化，但是并不是对应用程序需要显示的所有类型的图片都适用。有些时候你还是要实现自己的缓存机制，原因如下：

* `[UIImage imageNamed:]`方法仅仅适用于在应用程序资源束目录下的图片，但是大多数应用的许多图片都要从网络或者是用户的相机中获取，所以`[UIImage imageNamed:]`就没法用了。
* `[UIImage imageNamed:]`缓存用来存储应用界面的图片（按钮，背景等等）。如果对照片这种大图也用这种缓存，那么iOS系统就很可能会移除这些图片来节省内存。那么在切换页面时性能就会下降，因为这些图片都需要重新加载。对传送器的图片使用一个单独的缓存机制就可以把它和应用图片的生命周期解耦。
* `[UIImage imageNamed:]`缓存机制并不是公开的，所以你不能很好地控制它。例如，你没法做到检测图片是否在加载之前就做了缓存，不能够设置缓存大小，当图片没用的时候也不能把它从缓存中移除。


###自定义缓存

构建一个所谓的缓存系统非常困难。菲尔 卡尔顿曾经说过：“在计算机科学中只有两件难事：缓存和命名”。

如果要写自己的图片缓存的话，那该如何实现呢？让我们来看看要涉及哪些方面：

* 选择一个合适的缓存键 - 缓存键用来做图片的唯一标识。如果实时创建图片，通常不太好生成一个字符串来区分别的图片。在我们的图片传送带例子中就很简单，我们可以用图片的文件名或者表格索引。
* 提前缓存 - 如果生成和加载数据的代价很大，你可能想当第一次需要用到的时候再去加载和缓存。提前加载的逻辑是应用内在就有的，但是在我们的例子中，这也非常好实现，因为对于一个给定的位置和滚动方向，我们就可以精确地判断出哪一张图片将会出现。
* 缓存失效 - 如果图片文件发生了变化，怎样才能通知到缓存更新呢？这是个非常困难的问题（就像菲尔 卡尔顿提到的），但是幸运的是当从程序资源加载静态图片的时候并不需要考虑这些。对用户提供的图片来说（可能会被修改或者覆盖），一个比较好的方式就是当图片缓存的时候打上一个时间戳以便当文件更新的时候作比较。
* 缓存回收 - 当内存不够的时候，如何判断哪些缓存需要清空呢？这就需要到你写一个合适的算法了。幸运的是，对缓存回收的问题，苹果提供了一个叫做NSCache通用的解决方案

###NSCache
NSCache和NSDictionary类似。你可以通过`-setObject:forKey:`和`-object:forKey:`方法分别来插入，检索。和字典不同的是，NSCache在系统低内存的时候自动丢弃存储的对象。

NSCache用来判断何时丢弃对象的算法并没有在文档中给出，但是你可以使用`-setCountLimit:`方法设置缓存大小，以及`-setObject:forKey:cost:`来对每个存储的对象指定消耗的值来提供一些暗示。

 指定消耗数值可以用来指定相对的重建成本。如果对大图指定一个大的消耗值，那么缓存就知道这些物体的存储更加昂贵，于是当有大的性能问题的时候才会丢弃这些物体。你也可以用`-setTotalCostLimit:`方法来指定全体缓存的尺寸。

NSCache是一个普遍的缓存解决方案，我们创建一个比传送器案例更好的自定义的缓存类。（例如，我们可以基于不同的缓存图片索引和当前中间索引来判断哪些图片需要首先被释放）。但是NSCache对我们当前的缓存需求来说已经足够了；没必要过早做优化。

使用图片缓存和提前加载的实现来扩展之前的传送器案例，然后来看看是否效果更好

```
#import "ViewController.h"

@interface ViewController() 

@property (nonatomic, copy) NSArray *imagePaths;
@property (nonatomic, weak) IBOutlet UICollectionView *collectionView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    //set up data
    self.imagePaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"png" ￼inDirectory:@"Vacation Photos"];
    //register cell class
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.imagePaths count];
}

- (UIImage *)loadImageAtIndex:(NSUInteger)index
{
    //set up cache
    static NSCache *cache = nil;
    if (!cache) {
        cache = [[NSCache alloc] init];
    }
    //if already cached, return immediately
    UIImage *image = [cache objectForKey:@(index)];
    if (image) {
        return [image isKindOfClass:[NSNull class]]? nil: image;
    }
    //set placeholder to avoid reloading image multiple times
    [cache setObject:[NSNull null] forKey:@(index)];
    //switch to background thread
    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        //load image
        NSString *imagePath = self.imagePaths[index];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        //redraw image using device context
        UIGraphicsBeginImageContextWithOptions(image.size, YES, 0);
        [image drawAtPoint:CGPointZero];
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        //set image for correct image view
        dispatch_async(dispatch_get_main_queue(), ^{ //cache the image
            [cache setObject:image forKey:@(index)];
            //display the image
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem: index inSection:0]; UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
            UIImageView *imageView = [cell.contentView.subviews lastObject];
            imageView.image = image;
        });
    });
    //not loaded yet
    return nil;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    //dequeue cell
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
    //add image view
    UIImageView *imageView = [cell.contentView.subviews lastObject];
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        [cell.contentView addSubview:imageView];
    }
    //set or load image for this index
    imageView.image = [self loadImageAtIndex:indexPath.item];
    //preload image for previous and next index
    if (indexPath.item < [self.imagePaths count] - 1) {
        [self loadImageAtIndex:indexPath.item + 1]; }
    if (indexPath.item > 0) {
        [self loadImageAtIndex:indexPath.item - 1]; }
    return cell;
}

@end
```
果然效果更好了！当滚动的时候虽然还有一些图片进入的延迟，但是已经非常罕见了。缓存意味着我们做了更少的加载。这里提前加载逻辑非常粗暴，其实可以把滑动速度和方向也考虑进来，但这已经比之前没做缓存的版本好很多了。

##文件格式

图片加载性能取决于加载大图的时间和解压小图时间的权衡。很多苹果的文档都说PNG是iOS所有图片加载的最好格式。但这是极度误导的过时信息了。

PNG图片使用的无损压缩算法可以比使用JPEG的图片做到更快地解压，但是由于闪存访问的原因，这些加载的时间并没有什么区别。

展示了标准的应用程序加载不同尺寸图片所需要时间的一些代码。为了保证实验的准确性，我们会测量每张图片的加载和绘制时间来确保考虑到解压性能的因素。另外每隔一秒重复加载和绘制图片，这样就可以取到平均时间，使得结果更加准确。

```
#import "ViewController.h"

static NSString *const ImageFolder = @"Coast Photos";

@interface ViewController () 

@property (nonatomic, copy) NSArray *items;
@property (nonatomic, weak) IBOutlet UITableView *tableView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //set up image names
    self.items = @[@"2048x1536", @"1024x768", @"512x384", @"256x192", @"128x96", @"64x48", @"32x24"];
}

- (CFTimeInterval)loadImageForOneSec:(NSString *)path
{
    //create drawing context to use for decompression
    UIGraphicsBeginImageContext(CGSizeMake(1, 1));
    //start timing
    NSInteger imagesLoaded = 0;
    CFTimeInterval endTime = 0;
    CFTimeInterval startTime = CFAbsoluteTimeGetCurrent();
    while (endTime - startTime < 1) {
        //load image
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        //decompress image by drawing it
        [image drawAtPoint:CGPointZero];
        //update totals
        imagesLoaded ++;
        endTime = CFAbsoluteTimeGetCurrent();
    }
    //close context
    UIGraphicsEndImageContext();
    //calculate time per image
    return (endTime - startTime) / imagesLoaded;
}

- (void)loadImageAtIndex:(NSUInteger)index
{
    //load on background thread so as not to
    //prevent the UI from updating between runs dispatch_async(
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        //setup
        NSString *fileName = self.items[index];
        NSString *pngPath = [[NSBundle mainBundle] pathForResource:filename
                                                            ofType:@"png"
                                                       inDirectory:ImageFolder];
        NSString *jpgPath = [[NSBundle mainBundle] pathForResource:filename
                                                            ofType:@"jpg"
                                                       inDirectory:ImageFolder];
        //load
        NSInteger pngTime = [self loadImageForOneSec:pngPath] * 1000;
        NSInteger jpgTime = [self loadImageForOneSec:jpgPath] * 1000;
        //updated UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            //find table cell and update
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"PNG: %03ims JPG: %03ims", pngTime, jpgTime];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.items count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //dequeue cell
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
    }
    //set up cell
    NSString *imageName = self.items[indexPath.row];
    cell.textLabel.text = imageName;
    cell.detailTextLabel.text = @"Loading...";
    //load image
    [self loadImageAtIndex:indexPath.row];
    return cell;
}

@end
```

PNG和JPEG压缩算法作用于两种不同的图片类型：JPEG对于噪点大的图片效果很好；但是PNG更适合于扁平颜色，锋利的线条或者一些渐变色的图片。为了让测评的基准更加公平，我们用一些不同的图片来做实验：一张照片和一张彩虹色的渐变。JPEG版本的图片都用默认的Photoshop60%“高质量”设置编码。
 
![](lesson13_0.jpeg)

如结果所示，相对于不友好的PNG图片，相同像素的JPEG图片总是比PNG加载更快，除非一些非常小的图片、但对于友好的PNG图片，一些中大尺寸的图效果还是很好的。

所以对于之前的图片传送器程序来说，JPEG会是个不错的选择。如果用JPEG的话，一些多线程和缓存策略都没必要了。
    
但JPEG图片并不是所有情况都适用。如果图片需要一些透明效果，或者压缩之后细节损耗很多，那就该考虑用别的格式了。苹果在iOS系统中对PNG和JPEG都做了一些优化，所以普通情况下都应该用这种格式。也就是说在一些特殊的情况下才应该使用别的格式。


##移动端图片格式调研

**reference:http://blog.ibireme.com/2015/11/02/mobile_image_benchmark/**
*JPEG* 是目前最常见的图片格式，它诞生于 1992 年，是一个很古老的格式。它只支持有损压缩，其压缩算法可以精确控制压缩比，以图像质量换得存储空间。由于它太过常见，以至于许多移动设备的 CPU 都支持针对它的硬编码与硬解码。

*PNG* 诞生在 1995 年，比 JPEG 晚几年。它本身的设计目的是替代 GIF 格式，所以它与 GIF 有更多相似的地方。PNG 只支持无损压缩，所以它的压缩比是有上限的。相对于 JPEG 和 GIF 来说，它最大的优势在于支持完整的透明通道。

*GIF* 诞生于 1987 年，随着初代互联网流行开来。它有很多缺点，比如通常情况下只支持 256 种颜色、透明通道只有 1 bit、文件压缩比不高。它唯一的优势就是支持多帧动画，凭借这个特性，它得以从 Windows 1.0 时代流行至今，而且仍然大受欢迎。

在上面这些图片格式诞生后，也有不少公司或团体尝试对他们进行改进，或者创造其他更加优秀的图片格式，比如 JPEG 小组的 JPEG 2000、微软的 JPEG-XR、Google 的 WebP、个人开发者发布的 BPG、FLIF 等。它们相对于老牌的那几个图片格式来说有了很大的进步，但出于各种各样的原因，只有少数几个格式能够流行开来。下面三种就是目前实力比较强的新兴格式了：

*APNG* 是 Mozilla 在 2008 年发布的一种图片格式，旨在替换掉画质低劣的 GIF 动画。它实际上只是相当于 PNG 格式的一个扩展，所以 Mozilla 一直想把它合并到 PNG 标准里面去。然而 PNG 开发组并没有接受 APNG 这个扩展，而是一直在推进它自己的 MNG 动图格式。MNG 格式过于复杂以至于并没有什么系统或浏览器支持，而 APNG 格式由于简单容易实现，目前已经渐渐流行开来。Mozilla 自己的 Firefox 首先支持了 APNG，随后苹果的 Safari 也开始有了支持， Chrome 目前也已经尝试开始支持 ，可以说未来前景很好。

*WebP* 是 Google 在 2010 年发布的图片格式，希望以更高的压缩比替代 JPEG。它用 VP8 视频帧内编码作为其算法基础，取得了不错的压缩效果。它支持有损和无损压缩、支持完整的透明通道、也支持多帧动画，并且没有版权问题，是一种非常理想的图片格式。借由 Google 在网络世界的影响力，WebP 在几年的时间内已经得到了广泛的应用。看看你手机里的 App：微博、微信、QQ、淘宝、网易新闻等等，每个 App 里都有 WebP 的身影。Facebook 则更进一步，用 WebP 来显示聊天界面的贴纸动画。

*BPG* 是著名程序员 Fabrice Bellard 在去年 (2014年) 发布的一款超高压缩比的图片格式。这个程序员有些人可能感觉面生，但说起他的作品 FFmpeg、QEMU 大家想必是都知道的。BPG 使用 HEVC (即 H.265) 帧内编码作为其算法基础，就这点而言，它毋庸置疑是当下最为先进的图片压缩格式。相对于 JP2、JPEG-XR、WebP 来说，同等体积下 BPG 能提供更高的图像质量。另外，得益于它本身基于视频编码算法的特性，它能以非常小的文件体积保存多帧动画。 Fabrice Bellard 聪明的地方在于，他知道自己一个人无法得到各大浏览器厂商的支持，所以他还特地开发了 Javascript 版的解码器，任何浏览器只要加载了这个 76KB 大小的 JS 文件，就可以直接显示 BPG 格式的图片了。目前阻碍它流行的原因就是 HEVC 的版权问题和它较长的编码解码时间。尽管这个图片格式才刚刚发布一年，但已经有不少厂子开始试用了，比如阿里和腾讯。

![](lesson13_5.png)

Android 的图片编码解码是由 Skia 图形库负责的，Skia 通过挂接第三方开源库实现了常见的图片格式的编解码支持。目前来说，Android 原生支持的格式只有 JPEG、PNG、GIF、BMP 和 WebP (Android 4.0 加入)，在上层能直接调用的编码方式也只有 JPEG、PNG、WebP 这三种。目前来说 Android 还不支持直接的动图编解码。

iOS 底层是用 ImageIO.framework 实现的图片编解码。目前 iOS 原生支持的格式有：JPEG、JPEG2000、PNG、GIF、BMP、ICO、TIFF、PICT，自 iOS 8.0 起，ImageIO 又加入了 APNG、SVG、RAW 格式的支持。在上层，开发者可以直接调用 ImageIO 对上面这些图片格式进行编码和解码。对于动图来说，开发者可以解码动画 GIF 和 APNG、可以编码动画 GIF。

两个平台在导入第三方编解码库时，都多少对他们进行了一些修改，比如 Android 对 libjpeg 等进行的调整以更好的控制内存，iOS 对 libpng 进行了修改以支持 APNG，并增加了多线程编解码的特性。除此之外，iOS 专门针对 JPEG 的编解码开发了 AppleJPEG.framework，实现了性能更高的硬编码和硬解码，只有当硬编码解码失败时，libjpeg 才会被用到。

![](lesson13_6.png)

APNG 在文件体积上比 GIF 略有优势，解码时间相差不多。WebP 在体积和解码时间上都具有较大的优势。BPG 在体积上优势最大，但解码时间也最长。这么看来，APNG 和 WebP 都是不错的选择，而 BPG 还有待性能优化。