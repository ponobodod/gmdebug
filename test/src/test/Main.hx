package test;


class Main {

    public static function main() {
        utest.UTest.run([new BitShiftTest(),new HandlerTests()]);
    }
}