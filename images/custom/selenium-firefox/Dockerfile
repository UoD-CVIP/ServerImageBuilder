FROM uodcvip/cpu:latest

USER root
RUN apt update && apt install -yqq \
    gconf-service \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libfontconfig1 \
    libgdk-pixbuf2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libpango-1.0-0 \
    libxss1 \
    fonts-liberation \
    libappindicator1 \
    libnss3 \
    lsb-release \
    xdg-utils \
    firefox \
    firefox-geckodriver \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*


RUN python3 -m pip install --upgrade scrapy scrapy-selenium
USER ${NB_USER}
