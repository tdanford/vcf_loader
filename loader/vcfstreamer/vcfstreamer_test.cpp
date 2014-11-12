#include "gtest/gtest.h"

namespace {

  class StreamerTest : public ::testing::Test {
  protected:
    StreamerTest() {
      // You can do set-up work for each test here.
    }

    virtual ~StreamerTest() {
      // You can do clean-up work that doesn't throw exceptions here.
    }

    // If the constructor and destructor are not enough for setting up
    // and cleaning up each test, you can define the following methods:

    virtual void SetUp() {
      // Code here will be called immediately after the constructor (right
      // before each test).
    }

    virtual void TearDown() {
      // Code here will be called immediately after each test (right
      // before the destructor).
    }

    // Objects declared here can be used by all tests in the test case for Foo.
  };

  TEST(SimpleTest, TestsEqualityOfNumbers) {
    EXPECT_EQ(1, 0+1);
  }

}  // namespace

int main(int argc, char **argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}

