import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="echo", methods=["GET", "POST"])
def echo(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_body().decode("utf-8")
    return func.HttpResponse(
        body if body else "(empty request body)",
        status_code=200,
        mimetype="text/plain",
    )
