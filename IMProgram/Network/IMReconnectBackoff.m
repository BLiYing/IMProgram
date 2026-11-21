//  IMReconnectBackoff.m

#import "IMReconnectBackoff.h"

static const double kIMReconnectJitter = 0.2; ///< ±20%

NSTimeInterval IMReconnectDelay(NSInteger attempt, NSTimeInterval base, NSTimeInterval cap, double rand01) {
    double r = MIN(1.0, MAX(0.0, rand01));
    double exp = MIN(cap, base * pow(2, MIN(MAX(attempt, 0), 30))); // 封顶指数，防 pow 溢出
    return MAX(0.1, exp * (1.0 - kIMReconnectJitter + 2 * kIMReconnectJitter * r));
}
