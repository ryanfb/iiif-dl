var page = require('webpage').create(),
    system = require('system'),
    address;

if (system.args.length === 1) {
    console.log('Usage: jsonreqs.js <some URL>');
    phantom.exit(1);
} else {
    address = system.args[1];

    page.onResourceRequested = function (req) {
        if(/\.json$/.test(req['url'])) {
            console.log(req['url']);
        }
    };

    page.open(address, function (status) {
        if (status !== 'success') {
            console.log('FAIL to load the address');
        }
        setTimeout(function() {
            console.log('Timed out evaluating page');
            phantom.exit();}, 5000);
        page.evaluate();
        phantom.exit();
    });
}
