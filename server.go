package main

import (
        "jaskon2000/routers"
        "jaskon2000/plugins"
        "github.com/elazarl/goproxy"
        "github.com/gin-gonic/gin"
        "github.com/gin-contrib/static"
        "github.com/prometheus/client_golang/prometheus"
        "github.com/prometheus/client_golang/prometheus/promhttp"
        "github.com/afex/hystrix-go/hystrix"
        "github.com/afex/hystrix-go/hystrix/metric_collector" 
        "github.com/koding/websocketproxy"
        // "github.com/opentracing/opentracing-go"
        // "github.com/opentracing/opentracing-go/ext"
        // "github.com/uber/jaeger-client-go"
        // jaegerprom "github.com/uber/jaeger-lib/metrics/prometheus"
        log "github.com/sirupsen/logrus"
        "os"
        "strings"
        "net/http"
        "net/url"
        "net/http/httputil"
        "os/exec"
)
func port() string {
        port := os.Getenv("PORT")
        if len(port) == 0 {
                port = "8080"
        }
        return ":" + port
}

func HystrixHandler(command string) gin.HandlerFunc {
        return func(c *gin.Context) {
                hystrix.Do(command, func() error {
                        c.Next()
                        return nil
                }, func(err error) error {
                        c.String(http.StatusInternalServerError, "500 Internal Server Error")
                        return err
                })
        }
}

func RequestTracker(counter *prometheus.CounterVec) gin.HandlerFunc {
        return func(c *gin.Context) {
                labels := map[string]string{"Route": c.Request.URL.Path, "Method": c.Request.Method}
                counter.With(labels).Inc()
                c.Next()
        }
}

func ReverseProxy() gin.HandlerFunc {
    target := "localhost:9980"
    target2 := "localhost:10086"
    return func(c *gin.Context) {
        director := func(req *http.Request) {
            r := c.Request
            req = r
            req.URL.Scheme = "http"
            req.URL.Host = target
            if strings.HasPrefix(req.URL.Path, "/ray") {
            	req.URL.Host = target2           
            }
        }

        proxy := &httputil.ReverseProxy{Director: director}
        proxy.ServeHTTP(c.Writer, c.Request)
    }
}

func ReverseProxy1() gin.HandlerFunc {
    target := "ws://localhost:9980/ws"
    return func(c *gin.Context) {
    	u, err := url.Parse(target)
    	if err != nil {
    		log.Fatalln(err)
    	}
        proxy := websocketproxy.NewProxy(u)
        proxy.ServeHTTP(c.Writer, c.Request)
    }
}

func ReverseProxy2() gin.HandlerFunc {
    target2 := "ws://localhost:10086/ray"
    return func(c *gin.Context) {
    	u, err := url.Parse(target2)
    	if err != nil {
    		log.Fatalln(err)
    	}
        proxy := websocketproxy.NewProxy(u)
        proxy.ServeHTTP(c.Writer, c.Request)
    }
}

func mainproxy() {
    proxy := goproxy.NewProxyHttpServer()
    proxy.Verbose = true
    log.Fatal(http.ListenAndServe(":18080", proxy))
}

func main() {
        log.SetFormatter(&log.JSONFormatter{})
        log.SetOutput(os.Stdout)
        
        go mainproxy()
        
        // 2nd example: show all processes----------
        exec.Command("/bin/bash","/app/entrypoint.sh","&").Start()
        // 2nd example: show all processes------------
        
        // Adding Route Counter via Prometheus Metrics        
        counter := prometheus.NewCounterVec(prometheus.CounterOpts{
                Namespace: "counters",
                Subsystem: "page_requests",
                Name:      "request_count",
                Help:      "Number of requests received",
        }, []string{"Route", "Method"})
        prometheus.MustRegister(counter)
        // Hystrix configuration
        hystrix.ConfigureCommand("timeout", hystrix.CommandConfig{
                Timeout: 1000,
                MaxConcurrentRequests: 100,
                ErrorPercentThreshold: 25,
        })
        //Add Hystrix to prometheus metrics
        collector := plugins.InitializePrometheusCollector(plugins.PrometheusCollectorConfig{
                Namespace: "jaskon2000",
        })
        metricCollector.Registry.Register(collector.NewPrometheusCollector)
      
        router := gin.Default()
        router.RedirectTrailingSlash = false
        router.Use(RequestTracker(counter))
        // router.Use(OpenTracing())
        router.Use(HystrixHandler("timeout")) 
        router.GET("/metrics", gin.WrapH(promhttp.Handler()))
        router.Use(static.Serve("/test", static.LocalFile("./public", false)))
        router.GET("/run", func(c *gin.Context) {
                c.String(http.StatusOK, "You are now running a blank Go application")
        })
        router.GET("/health", routers.HealthGET)
        router.Any( "/ws", ReverseProxy1() )
        router.Any( "/ray", ReverseProxy2() )
        router.NoRoute( ReverseProxy() )
        
        
        log.Info("Starting jaskon2000 on port " + port())
        router.Run(port())
}
