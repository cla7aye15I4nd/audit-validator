
BRAND_NAME?="Tunnel"
BUILD_DATE=`date +%Y%m%d%H%M%S`
BUILD_COMMIT=`git describe --tags --always --dirty`

default:
	@echo "BRAND_NAME is: $(BRAND_NAME)"
	go build -ldflags "-X gitlab.weinvent.org/yangchenzhong/tunnel/utils.BrandName=${BRAND_NAME}\
		-X gitlab.weinvent.org/yangchenzhong/tunnel/utils.buildCommit=${BUILD_COMMIT}\
	    -X gitlab.weinvent.org/yangchenzhong/tunnel/utils.buildDate=${BUILD_DATE}"

newton:
	@echo "BRAND_NAME is: $(BRAND_NAME)"
	@echo "Modifying go.mod for newton version..."
	cp go.mod go.mod.bak
	echo "replace github.com/ethereum/go-ethereum => github.com/newtonproject/newchain v1.10.15-newton-dev" >> go.mod
	go mod tidy
	go build -ldflags "-X gitlab.weinvent.org/yangchenzhong/tunnel/utils.BrandName=${BRAND_NAME}\
			-X gitlab.weinvent.org/yangchenzhong/tunnel/utils.buildCommit=${BUILD_COMMIT}\
    	    -X gitlab.weinvent.org/yangchenzhong/tunnel/utils.buildDate=${BUILD_DATE}" -o tunnel-newton
	mv go.mod.bak go.mod
	go mod tidy

all: default newton
