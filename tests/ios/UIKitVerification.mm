#import <Foundation/Foundation.h>

#include <cstdio>

void verifyPagerObservations();
void verifySideDrawer();

int main()
{
  @autoreleasepool {
    verifyPagerObservations();
    verifySideDrawer();
    std::puts("iOS UIKit verification passed");
  }
}
