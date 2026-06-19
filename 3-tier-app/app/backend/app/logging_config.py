import logging
import sys

from pythonjsonlogger import jsonlogger


class RequestIdFilter(logging.Filter):
    def filter(self, record):
        try:
            from flask import g, has_request_context

            record.request_id = getattr(g, "request_id", "-") if has_request_context() else "-"
        except RuntimeError:
            record.request_id = "-"
        return True


def setup_logging():
    logger = logging.getLogger()
    if logger.handlers:
        return logger

    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(RequestIdFilter())
    formatter = jsonlogger.JsonFormatter(
        fmt="%(asctime)s %(levelname)s %(name)s %(message)s %(request_id)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger
